# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict bounded light journal replay separates complete immutable publication from exact-byte partial-tail plans.
import std/assertions
import ./[light_snapshot, light_state_cache, light_delta, light_journal_manifest, database_identity]
import ../codec/[bounded, state_layout]
import ../crypto/primitives
const EditBytes = 42

type
  LightReplayLimits* = object ## Total input, frame count and individual frame bounds independently limit replay work.
    bytes*: ByteLimit
    frames*: ElementLimit
    frame*: LightDeltaLimits
  LightReplayError* {.pure.} = enum ## Incomplete replay never exposes a successful prefix through a failed result.
    Uninitialized, None, InvalidFormat, LimitExceeded, WrongCheckpoint, SequenceExhausted,
    IncompleteTail, InvalidDelta, InvalidSelection, BackendFailure, NotIncomplete, ChangedInput
  LightJournalReplay* = object ## Private immutable progress becomes public only after complete strict replay or explicit planning.
    ready: bool
    image: PreparedLightSnapshot
    last: LightDeltaSequence
    count: uint64
    extent: int
  LightTailPlan* = object ## Explicit discard authority binds one fully authenticated prefix to the exact inspected transport.
    ready: bool
    retained: LightJournalReplay
    selected: StorageChecksum
    transport: StorageChecksum
    total: int
  LightReplayResult*[T] = object ## Selected inner causes carry no unverified image or partial candidate payload.
    case status: LightReplayError
    of None: completed: T
    of InvalidDelta: deltaCause: LightDeltaError
    of InvalidSelection: selectionCause: LightSelectionError
    else: discard
  Scan = object ## Private scanner scratch may retain progress on an incomplete suffix without granting public success.
    reason: LightReplayError
    progress: LightJournalReplay
    delta: LightDeltaError
    selection: LightSelectionError
func error*[T](outcome: LightReplayResult[T]): LightReplayError =
  ## Inspect the selected typed outer refusal alone.
  outcome.status
func value*[T](outcome: LightReplayResult[T]): T {.inline,
    requires: outcome.status == LightReplayError.None.} =
  ## Only complete success grants replay or repair-plan authority.
  outcome.completed
func deltaError*[T](outcome: LightReplayResult[T]): LightDeltaError {.requires:
    outcome.status == LightReplayError.InvalidDelta.} =
  ## Preserve only a selected frame refusal without a partial successor.
  outcome.deltaCause
func selectionError*[T](outcome: LightReplayResult[T]): LightSelectionError {.requires:
    outcome.status == LightReplayError.InvalidSelection.} =
  ## Preserve only a selected anchor refusal.
  outcome.selectionCause
func initialized*(replay: LightJournalReplay): bool =
  ## Default replay values safely report their absent publication authority.
  replay.ready
func initialized*(plan: LightTailPlan): bool =
  ## Default plans grant no discard extent or retained prefix.
  plan.ready
func snapshot*(replay: LightJournalReplay): PreparedLightSnapshot {.requires: replay.ready.} =
  ## Retain the authenticated prefix image independently of journal or planner lifetime.
  replay.image
func sequence*(replay: LightJournalReplay): LightDeltaSequence {.requires: replay.ready.} =
  ## Return the checkpoint baseline plus the exact admitted frame sequence.
  replay.last
func frameCount*(replay: LightJournalReplay): uint64 {.requires: replay.ready.} =
  ## Count only completely authenticated frames after the selected checkpoint.
  replay.count
func byteLength*(replay: LightJournalReplay): int {.requires: replay.ready.} =
  ## Return the complete anchor and authenticated frame prefix extent.
  replay.extent
func prefix*(plan: LightTailPlan): LightJournalReplay {.requires: plan.ready.} =
  ## Expose only the fully authenticated retained prefix, never the incomplete frame's candidate.
  plan.retained
func totalBytes*(plan: LightTailPlan): int {.requires: plan.ready.} =
  ## Bind a future explicit repair to the complete originally inspected byte extent.
  plan.total
func selectionChecksum*(plan: LightTailPlan): StorageChecksum {.requires: plan.ready.} =
  ## Revalidation must use the same exact selected manifest, not just an equal root.
  plan.selected
func fail[T](reason: LightReplayError): LightReplayResult[T] =
  ## Failed results contain no completed replay or plan authority.
  LightReplayResult[T](status: reason)
func refusal[T](scan: Scan): LightReplayResult[T] =
  ## Translate selected scratch causes without copying its retained progress into a failed public result.
  case scan.reason
  of LightReplayError.InvalidDelta:
    LightReplayResult[T](status: LightReplayError.InvalidDelta, deltaCause: scan.delta)
  of LightReplayError.InvalidSelection:
    LightReplayResult[T](status: LightReplayError.InvalidSelection, selectionCause: scan.selection)
  else: fail[T](scan.reason)
func number(input: openArray[byte], offset, width: int): uint64 {.requires:
    offset >= 0 and width >= 1 and width <= 8 and offset <= high(int)-width.} =
  ## Missing high bytes yield only a minimum possible value for partial-field bound checks.
  result = 0
  for index in 0..<width:
    if offset+index < input.len: result = result or (uint64(input[offset+index]) shl (8*index))
func boundedProduct(count, unit, maximum: uint64): uint64 =
  ## Saturate a nonnegative shape bound before multiplication; no untrusted product can wrap.
  if unit == 0 or count == 0: return 0
  if count > maximum div unit: return maximum
  count*unit
func payloadBounds(count, maximum, nodes, valueBytes: uint64): tuple[maximum, raw: uint64] =
  ## Unknown admits can distribute node counts and raw bytes independently within their per-edit ceilings.
  let nodeCount = boundedProduct(count, nodes, maximum div 64)
  let nodeBytes = nodeCount*64
  let rawLimit = if valueBytes < maximum: valueBytes else: maximum
  let raw = boundedProduct(count, rawLimit, maximum)
  let bound = if raw > maximum-nodeBytes: maximum else: nodeBytes+raw
  (maximum: bound, raw: raw)
func possiblePayload(count, size, nodes, valueBytes: uint64): bool =
  ## Sum-of-edits payloads are unions of 64-byte node intervals extended by bounded raw-byte totals.
  let bounds = payloadBounds(count, size, nodes, valueBytes)
  bounds.maximum == size and (bounds.raw >= 63 or size mod 64 <= bounds.raw)
proc completeNumber(input: openArray[byte], offset, width: int, lower, upper: uint64,
    selected: var uint64): bool {.requires:
    offset >= 0 and offset <= high(int)-8 and width >= 1 and width <= 8.} =
  ## Find the smallest bounded integer consistent with available low bytes, without shifting by 64 or rounding overflow.
  selected = 0
  if lower > upper: return false
  let available = max(0, min(width, input.len-offset))
  let minimum = number(input, offset, width)
  if minimum > upper: return false
  if available == width:
    if minimum < lower: return false
    selected = minimum
    return true
  if available == 0:
    selected = lower
    return true
  if minimum >= lower:
    selected = minimum
    return true
  let stride = 1'u64 shl (available*8)
  let steps = (lower-minimum-1) div stride+1
  if steps > (upper-minimum) div stride: return false
  selected = minimum+steps*stride # The quotient check proves both multiplication and addition inside upper.
  true
func keyCompletion(input: openArray[byte], offset, previous: int,
    following: uint64): bool {.requires:
    offset >= 0 and offset <= input.len and (previous < 0 or previous <= input.len-31).} =
  ## The smallest possible canonical key must leave enough distinct lexicographic successors for all remaining edits.
  let available = if input.len-offset < 31: input.len-offset else: 31
  var candidate = default(array[31, byte])
  for index in 0..<available: candidate[index] = input[offset+index]
  if previous >= 0:
    var relation = 0
    for index in 0..<31:
      if relation == 0 and candidate[index] != input[previous+index]:
        relation = if candidate[index] < input[previous+index]: -1 else: 1
    if relation <= 0:
      # Advance the previous complete key exactly once, preserving every already available prefix byte.
      for index in 0..<31: candidate[index] = input[previous+index]
      var slot = 30
      while slot >= 0 and candidate[slot] == 255:
        candidate[slot] = 0
        dec slot
      if slot < 0: return false
      candidate[slot] = byte(uint16(candidate[slot])+1)
      for index in 0..<available:
        if candidate[index] != input[offset+index]: return false
  for index in 0..<23:
    # Any smaller high prefix leaves at least 2^64 successors, more than a native bounded frame can request.
    if candidate[index] != 255: return true
  var tail = 0'u64
  for index in 23..<31: tail = (tail shl 8) or uint64(candidate[index])
  following <= high(uint64)-tail
proc possibleAdmit(input: openArray[byte], offset: int, capacity, following,
    nodeLimit, valueLimit: uint64): bool {.requires:
    offset >= 0 and offset <= high(int)-42 and nodeLimit <= 249 and capacity <= uint64(high(int)).} =
  ## Available node/raw fields must permit an exact current payload plus some bounded payload distribution among future edits.
  let maximumNode = min(nodeLimit, capacity div 64)
  var first = 0'u64
  var last = maximumNode
  if input.len > offset+32:
    # Hard depth below256 fixes the entire node count as soon as its low byte is present.
    first = number(input, offset+32, 2)
    last = first
  if first > maximumNode: return false
  for nodes in first..last:
    let remaining = capacity-nodes*64
    let future = payloadBounds(following, remaining, nodeLimit, valueLimit)
    let lower = if remaining > future.maximum: remaining-future.maximum else: 0'u64
    let upper = min(valueLimit, remaining)
    var raw = 0'u64
    if completeNumber(input, offset+34, 8, lower, upper, raw):
      # Known low raw bytes fix the future payload residue; an entirely unknown raw field may advance to the next valid interval.
      if future.raw < 63:
        let residue = (remaining-raw) mod 64
        if residue > future.raw:
          if input.len > offset+34: continue
          let adjustment = residue-future.raw
          if adjustment > upper-raw: continue
          raw += adjustment
      return true
  false
proc partialShape(input: openArray[byte], image: PreparedLightSnapshot,
    limits: LightDeltaLimits): LightDeltaError =
  ## Missing bytes cannot excuse already impossible integer, payload, key-cardinality or checksum constraints.
  let maximum = min(uint64(limits.bytes), uint64(high(int)))
  let allowance = min(uint64(limits.items), uint64(image.limits.cache.writes))
  let count = number(input, 160, 8)
  let bodyMinimum = number(input, 168, 8)
  if count > allowance or maximum < uint64(LightDeltaOverhead): return LightDeltaError.LimitExceeded
  let bodyMaximum = maximum-uint64(LightDeltaOverhead)
  if count > bodyMaximum div uint64(EditBytes) or bodyMinimum >
      bodyMaximum: return LightDeltaError.LimitExceeded
  let native = min(uint64(high(int) div sizeof(LightStateProof)), uint64(high(int) div sizeof(StateKey)))
  if count > native: return LightDeltaError.LengthOverflow
  if input.len < 168: return LightDeltaError.None
  let nodeLimit = min(249'u64, uint64(image.limits.cache.proof.nodes))
  let valueLimit = uint64(image.limits.cache.proof.valueBytes)
  let fixed = count*uint64(EditBytes)
  let bounds = payloadBounds(count, bodyMaximum-fixed, nodeLimit, valueLimit)
  var body = 0'u64
  if not completeNumber(input, 168, 8, fixed, fixed+bounds.maximum,
      body): return LightDeltaError.InvalidFormat
  if input.len > 168 and bounds.raw < 63 and (body-fixed) mod 64 >
      bounds.raw: return LightDeltaError.InvalidFormat
  if input.len < LightDeltaHeaderBytes: return LightDeltaError.None
  let stop = LightDeltaHeaderBytes+int(body)
  var cursor = LightDeltaHeaderBytes
  var previous = -1
  var remaining = count
  while remaining > 0:
    # Complete declared capacity and possible remaining payloads precede partial key and metadata inspection.
    if remaining > uint64((stop-cursor) div EditBytes): return LightDeltaError.InvalidFormat
    let capacity = uint64(stop-cursor)-remaining*uint64(EditBytes)
    if not possiblePayload(remaining, capacity, nodeLimit,
        valueLimit): return LightDeltaError.InvalidFormat
    if not keyCompletion(input, cursor, previous, remaining-1): return LightDeltaError.InvalidFormat
    if input.len-cursor < 31: return LightDeltaError.None
    previous = cursor
    if input.len-cursor < 32: return LightDeltaError.None
    let tag = input[cursor+31]
    if tag > 1: return LightDeltaError.InvalidFormat
    let nodes = number(input, cursor+32, 2)
    let size = number(input, cursor+34, 8)
    if tag == 0 and (nodes != 0 or size != 0): return LightDeltaError.InvalidFormat
    if nodes > nodeLimit or size > valueLimit: return LightDeltaError.LimitExceeded
    if tag == 0:
      if not possiblePayload(remaining-1, capacity, nodeLimit,
          valueLimit): return LightDeltaError.InvalidFormat
    elif not possibleAdmit(input, cursor, capacity, remaining-1, nodeLimit, valueLimit):
      return LightDeltaError.InvalidFormat
    if input.len-cursor < EditBytes: return LightDeltaError.None
    cursor += EditBytes
    dec remaining
    if nodes > capacity div 64 or size > capacity-nodes*64: return LightDeltaError.InvalidFormat
    let payload = int(nodes*64+size)
    if input.len-cursor < payload: return LightDeltaError.None
    cursor += payload
  if cursor != stop: return LightDeltaError.InvalidFormat
  if input.len > stop:
    # Available footer bytes must match the complete body checksum even before the footer is complete.
    let hashed = blake2b256(input.toOpenArray(0, stop-1))
    if hashed.error != CryptoError.None: return LightDeltaError.BackendFailure
    let checksum = array[32, byte](hashed.value)
    for index in 0..<input.len-stop:
      if input[stop+index] != checksum[index]: return LightDeltaError.ChecksumMismatch
  LightDeltaError.None
proc scan(input: openArray[byte], manifest: LightJournalManifest, checkpoint: PreparedLightSnapshot,
    limits: LightReplayLimits): Scan =
  ## Private sequential admission publishes no prefix on any malformed, complete-corrupt or over-budget suffix.
  if not manifest.initialized or not checkpoint.initialized: return Scan(
      reason: LightReplayError.Uninitialized)
  if uint64(input.len) > uint64(limits.bytes): return Scan(reason: LightReplayError.LimitExceeded)
  if array[32, byte](manifest.chainId) != array[32, byte](checkpoint.chainId) or
      array[32, byte](manifest.root) != array[32, byte](checkpoint.root) or
      array[32, byte](manifest.snapshotChecksum) != array[32, byte](checkpoint.checksum):
    return Scan(reason: LightReplayError.WrongCheckpoint)
  if input.len < LightJournalAnchorBytes: return Scan(reason: LightReplayError.InvalidFormat)
  let anchor = validateLightJournalAnchor(input.toOpenArray(0, LightJournalAnchorBytes-1), manifest, limits.bytes)
  if anchor != LightSelectionError.None:
    return Scan(reason: LightReplayError.InvalidSelection, selection: anchor)
  var progress = LightJournalReplay(ready: true, image: checkpoint, last: manifest.baseSequence,
    extent: LightJournalAnchorBytes)
  while progress.extent < input.len:
    # Each step checks frame and sequence capacity before extent parsing, proof work or addition.
    if progress.count >= uint64(limits.frames): return Scan(reason: LightReplayError.LimitExceeded)
    if uint64(progress.last) == high(uint64): return Scan(
        reason: LightReplayError.SequenceExhausted)
    let expected = LightDeltaSequence(uint64(progress.last)+1)
    let offset = progress.extent
    let extent = lightDeltaExtent(input.toOpenArray(offset, input.len-1), limits.frame)
    if extent.error == LightDeltaError.IncompleteFrame:
      # Prefix identity/sequence and partial syntax must both pass before explicit tail planning is possible.
      let partial = decodeLightDelta(input.toOpenArray(offset, input.len-1), progress.image,
          expected, limits.frame)
      if partial.error != LightDeltaError.IncompleteFrame:
        return Scan(reason: LightReplayError.InvalidDelta, delta: partial.error)
      let shape = partialShape(input.toOpenArray(offset, input.len-1), progress.image, limits.frame)
      if shape != LightDeltaError.None: return Scan(reason: LightReplayError.InvalidDelta, delta: shape)
      return Scan(reason: LightReplayError.IncompleteTail, progress: progress)
    if extent.error != LightDeltaError.None: return Scan(reason: LightReplayError.InvalidDelta,
        delta: extent.error)
    let complete = decodeLightDelta(input.toOpenArray(offset, offset+extent.value-1),
        progress.image, expected, limits.frame)
    if complete.error != LightDeltaError.None: return Scan(reason: LightReplayError.InvalidDelta,
        delta: complete.error)
    progress.image = complete.value.snapshot
    progress.last = expected
    inc progress.count
    progress.extent += extent.value
  Scan(reason: LightReplayError.None, progress: progress)
proc replayLightJournal*(input: openArray[byte], manifest: LightJournalManifest,
    checkpoint: PreparedLightSnapshot, limits: LightReplayLimits): LightReplayResult[
        LightJournalReplay] =
  ## Strict replay accepts only the complete selected journal; incomplete input exposes no retained prefix.
  let checked = scan(input, manifest, checkpoint, limits)
  if checked.reason != LightReplayError.None: return refusal[LightJournalReplay](checked)
  LightReplayResult[LightJournalReplay](status: LightReplayError.None, completed: checked.progress)
proc planLightJournalTail*(input: openArray[byte], manifest: LightJournalManifest,
    checkpoint: PreparedLightSnapshot, limits: LightReplayLimits): LightReplayResult[
        LightTailPlan] =
  ## Explicitly inspect a bounded incomplete suffix and bind its authenticated prefix to all original bytes.
  let checked = scan(input, manifest, checkpoint, limits)
  if checked.reason == LightReplayError.None: return fail[LightTailPlan](
      LightReplayError.NotIncomplete)
  if checked.reason != LightReplayError.IncompleteTail: return refusal[LightTailPlan](checked)
  let hashed = blake2b256(input)
  if hashed.error != CryptoError.None: return fail[LightTailPlan](LightReplayError.BackendFailure)
  LightReplayResult[LightTailPlan](status: LightReplayError.None,
    completed: LightTailPlan(ready: true, retained: checked.progress, selected: manifest.checksum,
      transport: StorageChecksum(array[32, byte](hashed.value)), total: input.len))
proc validateLightTailPlan*(input: openArray[byte], manifest: LightJournalManifest,
    plan: LightTailPlan): LightReplayError =
  ## A held-directory repair caller must revalidate exact current selection and complete bytes before any truncation.
  if not manifest.initialized or not plan.initialized: return LightReplayError.Uninitialized
  if input.len != plan.total or array[32, byte](manifest.checksum) != array[32, byte](plan.selected):
    return LightReplayError.ChangedInput
  let hashed = blake2b256(input)
  if hashed.error != CryptoError.None: return LightReplayError.BackendFailure
  if array[32, byte](hashed.value) != array[32, byte](
      plan.transport): return LightReplayError.ChangedInput
  LightReplayError.None
