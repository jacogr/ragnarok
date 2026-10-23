# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict bounded light journal replay separates complete immutable publication from exact-byte partial-tail plans.
import std/assertions
import ./[light_snapshot, light_delta, light_journal_manifest, database_identity]
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
func number(input: openArray[byte], offset, width: int): uint64 =
  ## Missing high bytes yield only a minimum possible value for partial-field bound checks.
  result = 0
  for index in 0..<width:
    if offset+index < input.len: result = result or (uint64(input[offset+index]) shl (8*index))
func compareKey(input: openArray[byte], left, right: int): int =
  ## Complete fixed-width keys are proved before canonical comparison.
  for index in 0..<31:
    if input[left+index] < input[right+index]: return -1
    if input[left+index] > input[right+index]: return 1
  0
proc partialShape(input: openArray[byte], image: PreparedLightSnapshot,
    limits: LightDeltaLimits): LightDeltaError =
  ## A partial frame must still admit a structurally possible bounded extension; IncompleteFrame alone grants no plan.
  let maximum = min(uint64(limits.bytes), uint64(high(int)))
  let allowance = min(uint64(limits.items), uint64(image.limits.cache.writes))
  let count = number(input, 160, 8)
  let body = number(input, 168, 8)
  if count > allowance or maximum < uint64(LightDeltaOverhead) or
      body > maximum-uint64(LightDeltaOverhead): return LightDeltaError.LimitExceeded
  if input.len < LightDeltaHeaderBytes: return LightDeltaError.None
  if count > body div uint64(EditBytes): return LightDeltaError.InvalidFormat
  let stop = LightDeltaHeaderBytes+int(body)
  var cursor = LightDeltaHeaderBytes
  var previous = -1
  var remaining = count
  while remaining > 0:
    # Declared body capacity must fit all remaining fixed headers before considering missing transport bytes.
    if remaining > uint64((stop-cursor) div EditBytes): return LightDeltaError.InvalidFormat
    if input.len-cursor < 31:
      # A partial key must admit at least one strictly larger completion than its predecessor.
      if previous >= 0:
        var relation = 0
        for index in 0..<31:
          let value = if cursor+index < input.len: input[cursor+index] else: 255'u8
          if relation == 0 and value != input[previous+index]:
            relation = if value < input[previous+index]: -1 else: 1
        if relation <= 0: return LightDeltaError.InvalidFormat
      return LightDeltaError.None
    if previous >= 0 and compareKey(input, previous, cursor) >=
        0: return LightDeltaError.InvalidFormat
    previous = cursor
    if input.len-cursor < 32: return LightDeltaError.None
    let tag = input[cursor+31]
    if tag > 1: return LightDeltaError.InvalidFormat
    let nodes = number(input, cursor+32, 2)
    let size = number(input, cursor+34, 8)
    if tag == 0 and (nodes != 0 or size != 0): return LightDeltaError.InvalidFormat
    if nodes > 249 or nodes > uint64(image.limits.cache.proof.nodes) or
        size > uint64(image.limits.cache.proof.valueBytes): return LightDeltaError.LimitExceeded
    if input.len-cursor < EditBytes: return LightDeltaError.None
    cursor += EditBytes
    dec remaining
    let capacity = uint64(stop-cursor)-remaining*uint64(EditBytes)
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
