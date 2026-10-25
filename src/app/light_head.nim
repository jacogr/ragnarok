# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently trusted light headers own bounded immutable history and partial verified evidence, never complete-map state.
## Cross-thread callers serialize shared ARC aliases as with the other immutable application owners.
import std/assertions
import ./[checkpoint_identity, checkpoint_trust]
import ../chain/[genesis, parameters]
import ../codec/[bounded, header, assurances, state_trie]
import ../crypto/primitives
import ../state/[proof_view, trie_proof]

const MaxLightHeaders* = 8 ## Header retention is independent of finality, complete state and physical storage generations.
type
  LightHeadLimits* = object ## Caller-selected header geometry is independent of fetch parameters and partial proof contents.
    header*: HeaderConfig
    headers*: ElementLimit
    headerBytes*: ByteLimit
    view*: ProofViewLimits
  LightHeaderIndex* = distinct uint32 ## Header-window positions never substitute for proof ordinals or protocol slots.
  LightHeaderSnapshot* = object ## Private canonical header bytes and copied metadata retain no complete StateStoreSnapshot.
    initialized: bool
    checkpoint: ApplicationCheckpointIdentity
    info: HeaderInfo
    wire: seq[byte]
  LightHeadData = ref object ## Acyclic immutable sharing keeps older heads/proofs readable after enrichment or advancement.
    records: seq[LightHeaderSnapshot]
    profile: HeaderConfig
    evidence: ProofView
  LightApplicationHead* = object ## Root authority comes from an independently trusted identity; proof knowledge remains explicitly partial.
    data: nil LightHeadData
  LightHeadError* {.pure.} = enum ## Failures expose no partially adopted header window or proof view.
    Uninitialized, None, MissingTrust, LimitExceeded, HeaderFailure, IdentityFailure,
      TrustMismatch, ProfileMismatch, SlotRegression, WrongParent, WrongPriorRoot,
      ViewFailure, InvalidFormat, InvalidIndex, BackendFailure
  LightHeadResult*[T] = object ## Only selected success exposes immutable application metadata or encoded bytes.
    case status: LightHeadError
    of None: completed: T
    of HeaderFailure: headerCause: HeaderError
    of IdentityFailure: identityCause: ApplicationCheckpointIdentityError
    of ViewFailure: viewCause: ProofViewError
    else: discard # Default and all refusals carry diagnostics alone.
func error*[T](outcome: LightHeadResult[T]): LightHeadError =
  ## Inspect a result before extracting any selected payload or subordinate cause.
  outcome.status
func value*[T](outcome: LightHeadResult[T]): T {.inline, requires: outcome.status ==
    LightHeadError.None.} =
  ## Failed/default operations never expose a usable head, header snapshot or byte prefix.
  outcome.completed
func headerError*[T](outcome: LightHeadResult[T]): HeaderError {.requires: outcome.status ==
    LightHeadError.HeaderFailure.} =
  ## Preserve the actual bounded structural header refusal.
  outcome.headerCause
func identityError*[T](outcome: LightHeadResult[T]): ApplicationCheckpointIdentityError {.requires: outcome.status ==
    LightHeadError.IdentityFailure.} =
  ## Preserve only an actual canonical identity decoding/encoding failure.
  outcome.identityCause
func viewError*[T](outcome: LightHeadResult[T]): ProofViewError {.requires: outcome.status ==
    LightHeadError.ViewFailure.} =
  ## Missing evidence, conflicting facts and resource ceilings retain their partial-view meaning.
  outcome.viewCause
func valid*(snapshot: LightHeaderSnapshot): bool =
  ## A default fixed record grants neither header nor posterior-root authority.
  snapshot.initialized
func valid*(head: LightApplicationHead): bool =
  ## Initialization remains distinct from a valid empty proof collection.
  head.data != nil
func len*(head: LightApplicationHead): int =
  ## Default heads retain no header window.
  let data = head.data
  if data == nil: 0 else: data.records.len
func identity*(snapshot: LightHeaderSnapshot): ApplicationCheckpointIdentity {.requires: snapshot.initialized.} =
  ## Return only immutable copied identity scalars, including the independently supplied posterior root.
  snapshot.checkpoint
func headerInfo*(snapshot: LightHeaderSnapshot): HeaderInfo {.requires: snapshot.initialized.} =
  ## Copied structural metadata exposes the prior root separately from the posterior identity root.
  snapshot.info
func byteLength*(snapshot: LightHeaderSnapshot): int =
  ## No raw mutable header buffer escapes its private snapshot.
  snapshot.wire.len
proc copyHeader*(snapshot: LightHeaderSnapshot, output: var openArray[byte]): bool =
  ## Caller storage is independent; insufficient capacity or a default record leaves it completely unchanged.
  if not snapshot.valid or output.len < snapshot.wire.len: return false # No incomplete transport or over-budget history is exposed.
  for index, octet in snapshot.wire: output[index] = octet # Complete checked capacity precedes the first copy.
  true
proc headerAt*(head: LightApplicationHead, index: LightHeaderIndex): LightHeadResult[
    LightHeaderSnapshot] =
  ## Only an initialized in-range immutable record can be selected from the bounded history window.
  let data = head.data
  if data == nil: return LightHeadResult[LightHeaderSnapshot](
      status: LightHeadError.Uninitialized) # Default owners retain no usable metadata or transport.
  if uint64(index) >= uint64(data.records.len): return LightHeadResult[LightHeaderSnapshot](
      status: LightHeadError.InvalidIndex) # Bounds precede narrowing and array access.
  LightHeadResult[LightHeaderSnapshot](status: LightHeadError.None, completed: data.records[int(
      uint32(index))])
proc current*(head: LightApplicationHead): LightHeadResult[LightHeaderSnapshot] =
  ## Every constructed head has at least one independently anchored current header.
  let data = head.data
  if data == nil: return LightHeadResult[LightHeaderSnapshot](
      status: LightHeadError.Uninitialized) # Default owners retain no usable metadata or transport.
  LightHeadResult[LightHeaderSnapshot](status: LightHeadError.None, completed: data.records[
      data.records.len-1])
proc stateRoot*(head: LightApplicationHead): StateRoot {.requires: head.data != nil.} =
  ## Partial evidence never computes this root; its authority is the captured current checkpoint identity.
  let data = head.data
  assert data != nil
  data.records[data.records.len-1].checkpoint.stateRoot
proc proofView*(head: LightApplicationHead): ProofView {.requires: head.data != nil.} =
  ## Return an immutable partial view; unrequested keys continue to mean MissingWitness, never absent.
  let data = head.data
  assert data != nil
  data.evidence
func limitsValid(limits: LightHeadLimits): bool =
  ## At most eight nonempty sealed headers bound all record-count arithmetic independently of host int width.
  uint64(limits.headers) in 1'u64..uint64(MaxLightHeaders) and uint64(limits.headerBytes) > 0
func sameProfile(left, right: HeaderConfig): bool =
  ## Resource byte caps may tighten; core/validator/epoch geometry remains independently fixed.
  let cores = uint64(left.cores) == uint64(right.cores)
  let validators = uint64(left.authorValidators) == uint64(right.authorValidators)
  let epoch = uint64(left.epochSlots) == uint64(right.epochSlots)
  cores and validators and epoch
proc sameParameters(left, right: ApplicationCheckpointIdentity): bool =
  ## Fixed canonical fetch bytes compare every profile field without consulting partial state.
  left.parameters.encodeParameters == right.parameters.encodeParameters
proc captureRecord(checkpoint: ApplicationCheckpointIdentity, wire: openArray[byte],
    limits: LightHeadLimits): LightHeadResult[LightHeaderSnapshot] =
  ## Private structural capture never creates operator trust from stored bytes; callers independently anchor the resulting history.
  if not checkpoint.ready: return LightHeadResult[LightHeaderSnapshot](
      status: LightHeadError.MissingTrust) # An independently captured current identity/header is required.
  if not limitsValid(limits): return LightHeadResult[LightHeaderSnapshot](
      status: LightHeadError.LimitExceeded) # Bounds precede allocation, copying and size conversion.
  let size = uint64(wire.len)
  let perHeader = min(uint64(MaxRecoveryHeaderBytes), uint64(limits.header.maxBytes))
  if size > uint64(limits.headerBytes) or size > perHeader:
    return LightHeadResult[LightHeaderSnapshot](status: LightHeadError.LimitExceeded)
  let configuration = checkpoint.parameters
  let cores = uint64(limits.header.cores) == configuration.get(coreCount)
  let epoch = uint64(limits.header.epochSlots) == configuration.get(epochPeriod)
  if not (cores and epoch):
    return LightHeadResult[LightHeaderSnapshot](status: LightHeadError.ProfileMismatch)
  let inspected = inspectHeader(wire, limits.header)
  if inspected.error != HeaderError.None: return LightHeadResult[LightHeaderSnapshot](
      status: LightHeadError.HeaderFailure,
      headerCause: inspected.error) # Structural parsing must succeed under the selected header geometry.
  if inspected.value.consumed != wire.len: return LightHeadResult[LightHeaderSnapshot](
      status: LightHeadError.InvalidFormat) # Only one complete local schema and exact framing are accepted.
  if uint64(inspected.value.unsigned.slot) != uint64(checkpoint.slot): return LightHeadResult[
      LightHeaderSnapshot](
      status: LightHeadError.TrustMismatch) # The exact copied identity and independent authority must agree.
  let hashed = blake2b256(wire)
  if hashed.error != CryptoError.None: return LightHeadResult[LightHeaderSnapshot](
      status: LightHeadError.BackendFailure) # A failed maintained hash primitive cannot validate byte bindings.
  if array[32, byte](hashed.value) != array[32, byte](checkpoint.blockHash): return LightHeadResult[
      LightHeaderSnapshot](
      status: LightHeadError.TrustMismatch) # The exact copied identity and independent authority must agree.
  var owned = newSeq[byte](wire.len)
  for index, octet in wire: owned[index] = octet # Capture is detached from the caller and every later mutable transport.
  LightHeadResult[LightHeaderSnapshot](status: LightHeadError.None, completed: LightHeaderSnapshot(
      initialized: true, checkpoint: checkpoint, info: inspected.value, wire: owned))
proc trustedRecord(trust: TrustedApplicationCheckpoint, limits: LightHeadLimits): LightHeadResult[
    LightHeaderSnapshot] =
  ## Only captured independent identity/header inputs can initialize or advance the application head.
  if not trust.ready: return LightHeadResult[LightHeaderSnapshot](
      status: LightHeadError.MissingTrust) # An independently captured current identity/header is required.
  if not limitsValid(limits): return LightHeadResult[LightHeaderSnapshot](
      status: LightHeadError.LimitExceeded) # Bounds precede allocation, copying and size conversion.
  let count = trust.sealedHeaderLength
  if uint64(count) > uint64(limits.headerBytes) or uint64(count) > uint64(
      limits.header.maxBytes): return LightHeadResult[LightHeaderSnapshot](
      status: LightHeadError.LimitExceeded) # Bounds precede allocation, copying and size conversion.
  var wire = newSeq[byte](count)
  if not trust.copySealedHeader(wire): return LightHeadResult[LightHeaderSnapshot](
      status: LightHeadError.MissingTrust) # An independently captured current identity/header is required.
  captureRecord(trust.identity, wire, limits)
proc viewFor(root: StateRoot, view: ProofView, limits: LightHeadLimits): LightHeadResult[ProofView] =
  ## Recheck inherited retained-fact quotas before adopting any partial evidence owner.
  if not view.valid: return LightHeadResult[ProofView](status: LightHeadError.ViewFailure,
      viewCause: ProofViewError.Uninitialized) # Uninitialized, foreign or over-budget evidence grants no view.
  if array[32, byte](view.root) != array[32, byte](root): return LightHeadResult[ProofView](
      status: LightHeadError.ViewFailure,
      viewCause: ProofViewError.WrongRoot) # Uninitialized, foreign or over-budget evidence grants no view.
  let checked = exportProofQueries(view, limits.view)
  if checked.error != ProofViewError.None: return LightHeadResult[ProofView](
      status: LightHeadError.ViewFailure,
      viewCause: checked.error) # Uninitialized, foreign or over-budget evidence grants no view.
  LightHeadResult[ProofView](status: LightHeadError.None, completed: view)
proc emptyView(root: StateRoot, limits: LightHeadLimits): ProofView =
  ## An explicit successful empty verified batch retains the trusted root while claiming no present or absent facts.
  let checked = verifyStateProofs([], root, default(StateProofLimits), default(StateProofBatchLimits))
  assert checked.error == StateProofError.None
  let captured = captureProofView(checked.value, root, limits.view)
  assert captured.error == ProofViewError.None
  captured.value
proc refused[T, U](outcome: LightHeadResult[U]): LightHeadResult[T] {.requires: outcome.status !=
    LightHeadError.None.} =
  ## Change only the absent success type while retaining every selected subordinate diagnostic.
  case outcome.status
  of LightHeadError.HeaderFailure: # Preserve the exact structural parser cause.
    LightHeadResult[T](status: LightHeadError.HeaderFailure, headerCause: outcome.headerCause)
  of LightHeadError.IdentityFailure: # Preserve the canonical identity codec cause.
    LightHeadResult[T](status: LightHeadError.IdentityFailure, identityCause: outcome.identityCause)
  of LightHeadError.ViewFailure: # Preserve partial-view admission semantics.
    LightHeadResult[T](status: LightHeadError.ViewFailure, viewCause: outcome.viewCause)
  else: LightHeadResult[T](status: outcome.status) # Remaining refused alternatives contain no payload.
proc captureLightHead*(trust: TrustedApplicationCheckpoint, view: ProofView,
    limits: LightHeadLimits): LightHeadResult[LightApplicationHead] =
  ## Capture one trusted current header and explicitly supplied matching partial facts without constructing a complete map.
  let record = trustedRecord(trust, limits)
  if record.error != LightHeadError.None: return refused[LightApplicationHead, LightHeaderSnapshot](record)
  let evidence = viewFor(record.value.checkpoint.stateRoot, view, limits)
  if evidence.error != LightHeadError.None: return refused[LightApplicationHead, ProofView](evidence)
  LightHeadResult[LightApplicationHead](status: LightHeadError.None,
      completed: LightApplicationHead(data: LightHeadData(records: @[record.value],
      profile: limits.header, evidence: evidence.value)))
proc captureLightHead*(trust: TrustedApplicationCheckpoint,
    limits: LightHeadLimits): LightHeadResult[LightApplicationHead] =
  ## Metadata-only initialization knows a root but no state facts, including no inferred absence.
  if not trust.ready: return LightHeadResult[LightApplicationHead](
      status: LightHeadError.MissingTrust) # An independently captured current identity/header is required.
  captureLightHead(trust, emptyView(trust.identity.stateRoot, limits), limits)
proc linked(parent, child: LightHeaderSnapshot): LightHeadError =
  ## Direct ancestry permits skipped slots but never equates a child's prior root with its independently trusted posterior root.
  if not sameParameters(parent.checkpoint, child.checkpoint): return LightHeadError.ProfileMismatch # Profile geometry is fixed independently of partial evidence.
  if uint64(child.checkpoint.slot) <= uint64(parent.checkpoint.slot): return LightHeadError.SlotRegression # Strict ordering permits gaps without adding or wrapping a slot.
  if array[32, byte](child.info.unsigned.parent) != array[32, byte](
      parent.checkpoint.blockHash): return LightHeadError.WrongParent # Direct ancestry names the exact sealed predecessor.
  if array[32, byte](child.info.unsigned.priorState) != array[32, byte](
      parent.checkpoint.stateRoot): return LightHeadError.WrongPriorRoot # The child prior root binds the parent posterior identity root.
  LightHeadError.None
proc fits(records: openArray[LightHeaderSnapshot], limits: LightHeadLimits): bool =
  ## Subtraction bounds the complete retained header transport before constructing a new head or encoded context.
  if not limitsValid(limits) or uint64(records.len) > uint64(
      limits.headers): return false # No incomplete transport or over-budget history is exposed.
  var total = 0'u64
  for record in records:
    let size = uint64(record.wire.len)
    if size > uint64(limits.header.maxBytes) or size > uint64(
        limits.headerBytes)-total: return false # No incomplete transport or over-budget history is exposed.
    total += size # Previous checks retain total <= headerBytes without wrapping.
  true
proc mergeLightProofs*(head: LightApplicationHead, batch: VerifiedStateProofBatch,
    limits: LightHeadLimits): LightHeadResult[LightApplicationHead] =
  ## Add only genuinely verified matching-root facts; immutable old heads remain independently readable.
  let data = head.data
  if data == nil: return LightHeadResult[LightApplicationHead](
      status: LightHeadError.Uninitialized) # Default owners retain no usable metadata or transport.
  if not sameProfile(data.profile, limits.header): return LightHeadResult[LightApplicationHead](
      status: LightHeadError.ProfileMismatch) # Profile geometry is fixed independently of partial evidence.
  if not fits(data.records, limits): return LightHeadResult[LightApplicationHead](
      status: LightHeadError.LimitExceeded) # Bounds precede allocation, copying and size conversion.
  let added = captureProofView(batch, head.stateRoot, limits.view)
  if added.error != ProofViewError.None: return LightHeadResult[LightApplicationHead](
      status: LightHeadError.ViewFailure,
      viewCause: added.error) # Uninitialized, foreign or over-budget evidence grants no view.
  let merged = mergeProofViews(data.evidence, added.value, limits.view)
  if merged.error != ProofViewError.None: return LightHeadResult[LightApplicationHead](
      status: LightHeadError.ViewFailure,
      viewCause: merged.error) # Uninitialized, foreign or over-budget evidence grants no view.
  LightHeadResult[LightApplicationHead](status: LightHeadError.None,
      completed: LightApplicationHead(data: LightHeadData(records: data.records,
      profile: limits.header, evidence: merged.value)))
proc advanceLightHead*(head: LightApplicationHead, trust: TrustedApplicationCheckpoint,
    view: ProofView, limits: LightHeadLimits): LightHeadResult[LightApplicationHead] =
  ## Independently trusted successor metadata binds direct ancestry and a fresh explicit proof collection under its posterior root.
  let data = head.data
  if data == nil: return LightHeadResult[LightApplicationHead](
      status: LightHeadError.Uninitialized) # Default owners retain no usable metadata or transport.
  if not sameProfile(data.profile, limits.header): return LightHeadResult[LightApplicationHead](
      status: LightHeadError.ProfileMismatch) # Profile geometry is fixed independently of partial evidence.
  let record = trustedRecord(trust, limits)
  if record.error != LightHeadError.None: return refused[LightApplicationHead, LightHeaderSnapshot](record)
  let link = linked(data.records[data.records.len-1], record.value)
  if link != LightHeadError.None: return LightHeadResult[LightApplicationHead](status: link)
  let evidence = viewFor(record.value.checkpoint.stateRoot, view, limits)
  if evidence.error != LightHeadError.None: return refused[LightApplicationHead, ProofView](evidence)
  let keep = min(data.records.len, int(uint64(limits.headers))-1)
  var records = newSeq[LightHeaderSnapshot](keep+1)
  for index in 0..<keep: records[index] = data.records[
      data.records.len-keep+index] # Only the bounded newest predecessor window survives.
  records[keep] = record.value
  if not fits(records, limits): return LightHeadResult[LightApplicationHead](
      status: LightHeadError.LimitExceeded) # Bounds precede allocation, copying and size conversion.
  LightHeadResult[LightApplicationHead](status: LightHeadError.None,
      completed: LightApplicationHead(data: LightHeadData(records: records, profile: limits.header,
      evidence: evidence.value)))
proc advanceLightHead*(head: LightApplicationHead, trust: TrustedApplicationCheckpoint,
    limits: LightHeadLimits): LightHeadResult[LightApplicationHead] =
  ## Omitted successor evidence explicitly starts unknown; facts from an old root are never implicitly carried forward.
  if not trust.ready: return LightHeadResult[LightApplicationHead](
      status: LightHeadError.MissingTrust) # An independently captured current identity/header is required.
  advanceLightHead(head, trust, emptyView(trust.identity.stateRoot, limits), limits)

const
  LightHeadMagic = "RAGNAROK-LIGHT-HEAD-V1\n"
  LightHeadPrefix = LightHeadMagic.len+3 # E2 independently selected author population, then E1 bounded header count.
proc put32(bytes: var seq[byte], offset: int, value: uint32) =
  ## Caller preflights the complete fixed field and full output before the first framing write.
  for index in 0..<4: bytes[offset+index] = byte((uint64(value) shr (index*8)) and 255)
proc get32(bytes: openArray[byte], offset: int): uint32 =
  ## Private callers establish all four readable bytes before forming this scalar.
  result = 0
  for index in 0..<4: result = result or (uint32(bytes[offset+index]) shl (index*8))
proc encodeLightHead*(head: LightApplicationHead, limit: ByteLimit): LightHeadResult[seq[byte]] =
  ## Encode only bounded header/identity history; partial proofs live separately and never become complete-map state.
  let data = head.data
  if data == nil: return LightHeadResult[seq[byte]](
      status: LightHeadError.Uninitialized) # Default owners retain no usable metadata or transport.
  let maximum = min(uint64(limit), uint64(high(int)))
  var total = uint64(LightHeadPrefix)
  if total > maximum: return LightHeadResult[seq[byte]](
      status: LightHeadError.LimitExceeded) # Bounds precede allocation, copying and size conversion.
  if uint64(data.profile.authorValidators) > uint64(high(uint16)): return LightHeadResult[seq[
      byte]](
      status: LightHeadError.ProfileMismatch) # Profile geometry is fixed independently of partial evidence.
  for ordinal in 0..<data.records.len:
    let record = data.records[ordinal] # Indexed access retains checks without a mutable ref-backed iterator borrow.
                                         # Fixed maximum record count/header size proves additions independently; subtraction also tightens the caller's output policy.
    let size = uint64(ApplicationCheckpointIdentityBytes)+4+uint64(record.wire.len)
    if size > maximum-total: return LightHeadResult[seq[byte]](
        status: LightHeadError.LimitExceeded) # Bounds precede allocation, copying and size conversion.
    total += size
  var bytes = newSeq[byte](int(total))
  for index, character in LightHeadMagic: bytes[index] = byte(
      character) # Distinct local version accepts no full-map or raw opaque context fallback.
  let validators = uint64(data.profile.authorValidators)
  bytes[LightHeadMagic.len] = byte(validators and 255)
  bytes[LightHeadMagic.len+1] = byte((validators shr 8) and 255)
  bytes[LightHeadMagic.len+2] = byte(data.records.len)
  var cursor = LightHeadPrefix
  for ordinal in 0..<data.records.len:
    let record = data.records[ordinal] # Indexed access retains checks without a mutable ref-backed iterator borrow.
    let encoded = encodeApplicationCheckpointIdentity(record.checkpoint, ByteLimit(uint64(
        ApplicationCheckpointIdentityBytes)))
    if encoded.error != ApplicationCheckpointIdentityError.None: return LightHeadResult[seq[byte]](
        status: LightHeadError.IdentityFailure,
        identityCause: encoded.error) # Canonical identity refusal grants no record or encoded prefix.
    for octet in encoded.value:
      bytes[cursor] = octet
      inc cursor # Complete measurement preceded all writes; failed encoding returns no buffer prefix.
    put32(bytes, cursor, uint32(record.wire.len))
    cursor += 4
    for octet in record.wire:
      bytes[cursor] = octet
      inc cursor # Immutable private header storage cannot alias the detached output.
  LightHeadResult[seq[byte]](status: LightHeadError.None, completed: bytes)
proc restoreLightHead*(bytes: openArray[byte], expected: TrustedApplicationCheckpoint,
    view: ProofView, limits: LightHeadLimits, contextBytes: ByteLimit): LightHeadResult[
        LightApplicationHead] =
  ## Strict local history restoration still requires independently supplied current identity/header authority and matching partial facts.
  if not expected.ready: return LightHeadResult[LightApplicationHead](
      status: LightHeadError.MissingTrust) # An independently captured current identity/header is required.
  if not limitsValid(limits) or uint64(bytes.len) > uint64(contextBytes): return LightHeadResult[
      LightApplicationHead](
      status: LightHeadError.LimitExceeded) # Bounds precede allocation, copying and size conversion.
  if bytes.len < LightHeadPrefix: return LightHeadResult[LightApplicationHead](
      status: LightHeadError.InvalidFormat) # Only one complete local schema and exact framing are accepted.
  for index, character in LightHeadMagic:
    if bytes[index] != byte(character): return LightHeadResult[LightApplicationHead](
        status: LightHeadError.InvalidFormat) # No alternative schema or inferred node mode.
  let validators = uint64(bytes[LightHeadMagic.len]) or (uint64(bytes[LightHeadMagic.len+1]) shl 8)
  if validators != uint64(limits.header.authorValidators): return LightHeadResult[
      LightApplicationHead](
      status: LightHeadError.ProfileMismatch) # Profile geometry is fixed independently of partial evidence.
  let count = int(bytes[LightHeadMagic.len+2])
  if count == 0: return LightHeadResult[LightApplicationHead](
      status: LightHeadError.InvalidFormat) # Only one complete local schema and exact framing are accepted.
  if uint64(count) > uint64(limits.headers): return LightHeadResult[LightApplicationHead](
      status: LightHeadError.LimitExceeded) # Bounds precede allocation, copying and size conversion.
  var cursor = LightHeadPrefix
  var totalHeaders = 0'u64
  var records: seq[LightHeaderSnapshot] = @[]
  for ordinal in 0..<count:
    # Establish every fixed identity/length field before slicing, adding or narrowing an untrusted size.
    if bytes.len-cursor < ApplicationCheckpointIdentityBytes+4: return LightHeadResult[
        LightApplicationHead](
        status: LightHeadError.InvalidFormat) # Only one complete local schema and exact framing are accepted.
    let decoded = decodeApplicationCheckpointIdentity(bytes.toOpenArray(cursor,
        cursor+ApplicationCheckpointIdentityBytes-1), ByteLimit(uint64(
        ApplicationCheckpointIdentityBytes)))
    if decoded.error != ApplicationCheckpointIdentityError.None: return LightHeadResult[
        LightApplicationHead](status: LightHeadError.IdentityFailure,
        identityCause: decoded.error) # Canonical identity refusal grants no record or encoded prefix.
    if not sameParameters(decoded.value, expected.identity): return LightHeadResult[
        LightApplicationHead](
        status: LightHeadError.ProfileMismatch) # Profile geometry is fixed independently of partial evidence.
    cursor += ApplicationCheckpointIdentityBytes
    let size = uint64(get32(bytes, cursor))
    cursor += 4
    if size == 0 or size > uint64(bytes.len-cursor): return LightHeadResult[LightApplicationHead](
        status: LightHeadError.InvalidFormat) # Only one complete local schema and exact framing are accepted.
    if size > uint64(MaxRecoveryHeaderBytes) or size > uint64(
        limits.headerBytes)-totalHeaders: return LightHeadResult[LightApplicationHead](
        status: LightHeadError.LimitExceeded) # Bounds precede allocation, copying and size conversion.
    totalHeaders += size
    let record = captureRecord(decoded.value, bytes.toOpenArray(cursor, cursor+int(size)-1), limits)
    if record.error != LightHeadError.None: return refused[LightApplicationHead,
        LightHeaderSnapshot](record)
    if records.len > 0:
      # Every older posterior root is bound by the next sealed header; the final record is anchored to independent current trust below.
      let link = linked(records[records.len-1], record.value)
      if link != LightHeadError.None: return LightHeadResult[LightApplicationHead](status: link)
    records.add(record.value)
    cursor += int(size)
  if cursor != bytes.len: return LightHeadResult[LightApplicationHead](
      status: LightHeadError.InvalidFormat) # Only one complete local schema and exact framing are accepted.
  if not sameApplicationCheckpoint(records[records.len-1].checkpoint,
      expected.identity): return LightHeadResult[LightApplicationHead](
      status: LightHeadError.TrustMismatch) # The exact copied identity and independent authority must agree.
  let evidence = viewFor(expected.identity.stateRoot, view, limits)
  if evidence.error != LightHeadError.None: return refused[LightApplicationHead, ProofView](evidence)
  LightHeadResult[LightApplicationHead](status: LightHeadError.None,
      completed: LightApplicationHead(data: LightHeadData(records: records, profile: limits.header,
      evidence: evidence.value)))

func sameLightHead*(left, right: LightApplicationHead): bool =
  ## Exact immutable source incarnation includes partial knowledge; matching header/root alone cannot prove matching cached facts.
  left.data != nil and left.data == right.data
proc headerProfile*(head: LightApplicationHead): HeaderConfig {.requires: head.data != nil.} =
  ## Configured geometry is fixed caller metadata, never inferred from partial state or advertised as verified roster contents.
  let data = head.data
  assert data != nil
  data.profile
