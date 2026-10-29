# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Distinct light paged ownership publishes trusted header metadata and partial proofs together.
## Startup requires independent current trust; passive snapshots never perform native IO.
import std/assertions
import ./head as light_head
import ../checkpoint/[trust as checkpoint_trust, identity as checkpoint_identity]
import ../../state/proof/view as proof_view
import ../../state/trie_proof
import ../../state/paged/proof_view as paged_proof_view
import ../../storage/paged/[store as paged_store, stream as paged_stream, codec as paged_codec]
import ../../storage/managed/manifest as managed_manifest
import ../../storage/light/delta as light_delta
import ../../storage/durability
import ../../storage/file/errors as file_errors
import ../../storage/state_proof as nativeproof
import ../../storage/light/state_cache as nativecache
import ../../codec/bounded
import ../../codec/state/[layout as state_layout, trie as state_trie]
const
  ContextMagic = "RAGNAROK-LIGHT-PAGED-CONTEXT-V1\n"
  ContextPrefix = ContextMagic.len+9 # One explicit predecessor tag and E8 inner byte length.
type
  LightPagedLimits* = object ## Native, state-proof retention, inventory and application context quotas remain independent.
    native*: PagedNativeConfig
    head*: LightHeadLimits
    proofs*: PagedProofViewLimits
    inventory*: PagedWorkLimits
    contextBytes*: ByteLimit
  SnapshotData = ref object ## Immutable acyclic ownership survives publication, retirement and store close.
    head: LightApplicationHead
    selected: PagedManifest
    limits: LightPagedLimits
  LightStorageSnapshot* = object ## A partial view and trusted header window never provide complete-map execution authority.
    data: nil SnapshotData
  StoreCache = ref object ## Only the excluded IO owner mutates current selection, pending retirement and uncertainty.
    current: nil SnapshotData
    previous: PagedManifest
    healthy, pending: bool
  LightPagedStore* = object ## A move-only explicit-close owner holds one native writer and passive application cache.
    writer: PagedWriter
    cache: nil StoreCache
  PreparedData = ref object ## Private immutable target and encoded metadata retain no native descriptor or callback.
    head: LightApplicationHead
    inner: seq[byte]
    count, payload: uint64
  PreparedLightPublication* = object ## Exact source snapshot incarnation rejects stale and foreign prepared application updates.
    source: nil SnapshotData
    target: nil PreparedData
  PreparedLightRetirement* = object ## A passive job binds the cache incarnation, current selection and expected previous artifact.
    owner: nil StoreCache
    current: nil SnapshotData
    previous: PagedManifest
  LightStoreError* {.pure.} = enum ## Default/failure cases expose only reasons, never incomplete snapshots or mutation authority.
    Uninitialized, None, Busy, NotReady, LimitExceeded, PolicyMismatch, TrustMismatch,
    InvalidFormat, StaleView, RetirementPending, RecoveryRequired, HeadFailure,
    ViewFailure, NativeFailure, FileFailure
  LightStoreResult*[T] = object ## Only complete success grants its selected application result.
    case status: LightStoreError
    of None: completed: T
    of HeadFailure: headCause: LightHeadError
    of ViewFailure: viewCause: PagedProofViewResult[ProofView]
    of NativeFailure: nativeCause: PagedNativeResult[bool]
    of FileFailure: fileCause: FileError
    else: discard               # Plain refusals own no selected payload.
  DecodedContext = object ## Native authentication precedes parsing; an independently expected previous manifest grants bounded retirement authority.
    previous: PagedManifest
    inner: seq[byte]
func error*[T](outcome: LightStoreResult[T]): LightStoreError =
  ## Observe the selected stage without authorizing extraction.
  outcome.status
func value*[T](outcome: LightStoreResult[T]): T {.inline, requires: outcome.status ==
    LightStoreError.None.} =
  ## Checked success alone exposes an immutable completed result.
  outcome.completed
func nativeFailure*[T](outcome: LightStoreResult[T]): PagedNativeResult[
    bool] {.requires: outcome.status == LightStoreError.NativeFailure.} =
  ## Preserve exact native IO, stream and proof uncertainty without a successful native payload.
  outcome.nativeCause
func headError*[T](outcome: LightStoreResult[T]): LightHeadError {.requires: outcome.status ==
    LightStoreError.HeadFailure.} =
  ## Header/profile/link refusal remains distinct from physical storage uncertainty.
  outcome.headCause
func viewFailure*[T](outcome: LightStoreResult[T]): PagedProofViewResult[
    ProofView] {.requires: outcome.status == LightStoreError.ViewFailure.} =
  ## This nested result is always failed and contains no partial materialized proof view.
  outcome.viewCause
func fileError*[T](outcome: LightStoreResult[T]): FileError {.requires: outcome.status ==
    LightStoreError.FileFailure.} =
  ## Inspect a real file or resource retirement refusal.
  outcome.fileCause
func nativeFailed[T, U](outcome: PagedNativeResult[U]): LightStoreResult[
    T] {.requires: outcome.error != PagedNativeError.None.} =
  ## Convert only a failed native alternative while preserving its original selected cause.
  LightStoreResult[T](status: LightStoreError.NativeFailure, nativeCause: outcome.failure)
func opened*(store: LightPagedStore): bool =
  ## Passive lifetime observation never touches CURRENT or native identity.
  store.writer.opened
proc `=copy`*(destination: var LightPagedStore, source: LightPagedStore) {.error.}
  ## Native ownership cannot be copied between light application stores.
proc `=dup`*(source: LightPagedStore): LightPagedStore {.error.}
  ## Retaining a partial snapshot never duplicates the unique writer.
proc `=wasMoved`*(store: var LightPagedStore) {.nodestroy, inline.} =
  ## Disarm transferred fields through their own move hooks; never destroy the destination resources.
  `=wasMoved`(store.writer)
  `=wasMoved`(store.cache)

proc `=destroy`*(store: LightPagedStore) =
  ## Explicit close joins the owning runtime before the native owner leaves scope.
  assert not store.opened
proc close*(store: var LightPagedStore): FileError =
  ## Retained external snapshots remain readable after native handles and the mutable cache retire.
  result = store.writer.close
  store.cache = nil
func valid*(snapshot: LightStorageSnapshot): bool =
  ## Default snapshots grant no trusted metadata or partial proof access.
  snapshot.data != nil
proc head*(snapshot: LightStorageSnapshot): LightApplicationHead {.requires: snapshot.data != nil.} =
  ## Immutable metadata and proof ownership outlive every native source.
  let data = snapshot.data
  assert data != nil
  data.head
proc manifest*(snapshot: LightStorageSnapshot): PagedManifest {.requires: snapshot.data != nil.} =
  ## Passive physical metadata never substitutes for independent consensus trust.
  let data = snapshot.data
  assert data != nil
  data.selected
proc snapshot*(store: LightPagedStore): LightStoreResult[LightStorageSnapshot] =
  ## Dispatcher reads use only already admitted cached ownership and perform zero native calls.
  let cache = store.cache
  if cache == nil or not store.opened: return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.Uninitialized) # No startup prefix grants read authority.
  if not cache.healthy: return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.RecoveryRequired) # A fresh open resolves uncertain physical selection.
  let current = cache.current
  if current == nil: return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.NotReady) # Only completely restored application state is cached.
  LightStoreResult[LightStorageSnapshot](status: LightStoreError.None,
      completed: LightStorageSnapshot(data: current))
func retirementPending*(store: LightPagedStore): bool =
  ## Passive bounded-backpressure observation never scans native names.
  let cache = store.cache
  cache != nil and cache.pending
proc quarantine(store: LightPagedStore) =
  ## IO uncertainty invalidates future facade operations but never changes retained immutable snapshots.
  let cache = store.cache
  if cache != nil: cache.healthy = false # Only the excluded owner mutates this latch.
proc copyBytes(bytes: openArray[byte]): seq[byte] =
  ## The caller bounds this extent before any detached transport allocation.
  result = newSeq[byte](bytes.len)
  for index in 0..<bytes.len: result[index] = bytes[index] # No mutable source backing escapes.
func policyValid(limits: LightPagedLimits): bool =
  ## Reserve the worst-case envelope independently of logical proof bytes and native total extent.
  let cap = uint64(limits.native.limits.contextBytes)
  let overhead = uint64(ContextPrefix+PagedManifestBytes)
  let inner = uint64(limits.contextBytes)
  inner > 0 and overhead <= cap and inner <= cap-overhead and
    overhead <= uint64(limits.native.limits.dataset.bytes) and inner <= uint64(
        limits.native.limits.dataset.bytes)-overhead
proc envelope(inner: openArray[byte], previous: PagedManifest,
    limits: LightPagedLimits): LightStoreResult[seq[byte]] =
  ## The exact predecessor is inside the same authenticated native artifact as the new partial proofs and header metadata.
  if not policyValid(limits) or inner.len == 0 or uint64(inner.len) > uint64(
      limits.contextBytes): return LightStoreResult[seq[byte]](
      status: LightStoreError.LimitExceeded) # Refuse before computing the allocation extent.
  let prefix = ContextPrefix+(if previous.initialized: PagedManifestBytes else: 0)
  if inner.len > high(int)-prefix: return LightStoreResult[seq[byte]](
      status: LightStoreError.LimitExceeded) # Host addition cannot wrap.
  var bytes = newSeq[byte](prefix+inner.len)
  for index, character in ContextMagic: bytes[index] = byte(
      character) # One strict local schema, distinct from full application context.
  bytes[ContextMagic.len] = if previous.initialized: 1'u8 else: 0'u8
  for index in 0..<8: bytes[ContextMagic.len+1+index] = byte((uint64(inner.len) shr (8*index)) and
      255) # Fixed E8 length.
  if previous.initialized:
    # A complete canonical manifest binds root, counters, extent and local digest rather than an inferred filename.
    let encoded = previous.bytes
    for index in 0..<PagedManifestBytes: bytes[ContextPrefix+index] = encoded[index]
  for index in 0..<inner.len: bytes[prefix+index] = inner[index] # Detached immutable context capture.
  LightStoreResult[seq[byte]](status: LightStoreError.None, completed: bytes)
proc decodeContext(bytes: openArray[byte], selected: PagedManifest,
    limits: LightPagedLimits): LightStoreResult[DecodedContext] =
  ## Complete native authentication grants byte integrity; independent current trust still anchors application interpretation.
  if not policyValid(limits) or uint64(bytes.len) > uint64(
      limits.native.limits.contextBytes): return LightStoreResult[DecodedContext](
      status: LightStoreError.LimitExceeded) # Bound all source bytes before parsing.
  if bytes.len <= ContextPrefix: return LightStoreResult[DecodedContext](
      status: LightStoreError.InvalidFormat) # No raw context or full-store fallback.
  for index, character in ContextMagic:
    # Every version byte must match exactly before the tag or embedded predecessor is interpreted.
    if bytes[index] != byte(character): return LightStoreResult[DecodedContext](
        status: LightStoreError.InvalidFormat)
  let tag = bytes[ContextMagic.len]
  if tag > 1: return LightStoreResult[DecodedContext](
      status: LightStoreError.InvalidFormat) # Unknown alternatives grant no deletion authority.
  let prefix = ContextPrefix+(if tag == 1: PagedManifestBytes else: 0)
  if prefix >= bytes.len: return LightStoreResult[DecodedContext](
      status: LightStoreError.InvalidFormat) # Prove the complete fixed predecessor before slicing.
  var size = 0'u64
  for index in 0..<8: size = size or (uint64(bytes[ContextMagic.len+1+index]) shl (
      8*index)) # Every E8 byte is in the proved prefix.
  if size != uint64(bytes.len-prefix) or size > uint64(
      limits.contextBytes): return LightStoreResult[DecodedContext](
      status: LightStoreError.InvalidFormat) # Reject noncanonical length and trailing transport.
  var previous = default(PagedManifest)
  if tag == 0:
    # This facade exposes no compaction or silent context reset; only the initial physical epoch lacks a predecessor.
    if uint64(selected.epoch) != 1 or uint64(selected.sequence) != 0: return LightStoreResult[
        DecodedContext](status: LightStoreError.InvalidFormat)
  else:
    # Read the old root only as part of expected-content retirement metadata, never as current consensus authority.
    var root = default(array[32, byte])
    for index in 0..<32: root[index] = bytes[ContextPrefix+65+index] # The entire 193-byte predecessor was bounded above.
    let decoded = decodePagedManifest(bytes.toOpenArray(ContextPrefix, prefix-1),
        limits.native.chain,
      StateRoot(root), limits.native.limits.dataset, ByteLimit(PagedManifestBytes), true)
    if decoded.error != PagedCodecError.None: return LightStoreResult[DecodedContext](
        status: LightStoreError.InvalidFormat) # Strict chain/schema/caps precede any old-file authority.
    previous = decoded.value
    let epoch = uint64(previous.epoch)
    if epoch == high(uint64) or epoch+1 != uint64(selected.epoch): return LightStoreResult[
        DecodedContext](
        status: LightStoreError.InvalidFormat) # Only this facade's immediate predecessor is admissible.
    let sequence = uint64(previous.sequence)
    if array[32, byte](previous.root) == array[32, byte](selected.root):
      # Same-root replacement increments ordinary sequence; overflow is refused before addition.
      if sequence == high(uint64) or sequence+1 != uint64(
          selected.sequence): return LightStoreResult[DecodedContext](
          status: LightStoreError.InvalidFormat)
    elif sequence != uint64(selected.sequence):
      return LightStoreResult[DecodedContext](status: LightStoreError.InvalidFormat) # Different-root advancement preserves ordinary sequence.
  LightStoreResult[DecodedContext](status: LightStoreError.None,
    completed: DecodedContext(previous: previous, inner: copyBytes(bytes.toOpenArray(prefix, bytes.high))))
proc prepare(head: LightApplicationHead, limits: LightPagedLimits): LightStoreResult[PreparedData] =
  ## Recheck inherited header/profile and all retained proof/payload quotas before native namespace mutation.
  if not head.valid: return LightStoreResult[PreparedData](
      status: LightStoreError.NotReady) # Defaults grant no root or metadata.
  if not policyValid(limits): return LightStoreResult[PreparedData](
      status: LightStoreError.PolicyMismatch) # Explicit V2 and complete envelope capacity are mandatory.
  let empty = verifyStateProofs(newSeq[StateProofQuery](0), head.stateRoot, limits.proofs.proof,
      limits.proofs.batch)
  if empty.error != trie_proof.StateProofError.None: return LightStoreResult[PreparedData](
      status: LightStoreError.LimitExceeded) # No successful placeholder batch is invented.
  let recaptured = mergeLightProofs(head, empty.value, limits.head)
  if recaptured.error != LightHeadError.None: return LightStoreResult[PreparedData](
      status: LightStoreError.HeadFailure,
      headCause: recaptured.error) # Recheck profile, retained window and view under the selected storage policy.
  let retained = recaptured.value
  let view = retained.proofView
  let count = uint64(view.len)
  if count > uint64(limits.native.limits.dataset.entries) or count > uint64(
      limits.proofs.batch.items) or count > uint64(
      limits.proofs.view.items): return LightStoreResult[PreparedData](
      status: LightStoreError.LimitExceeded) # Query counts are independent of complete-map population.
  var nodes = 0'u64
  var values = 0'u64
  var payload = 0'u64
  for index in 0..<view.len:
    # Immutable lookup/witness access copies no value payload during preflight.
    let proof = view.lookupAt(index).value.witness
    let n = uint64(proof.len)
    let v = uint64(proof.suppliedByteLength.value)
    if n > 249 or n > uint64(limits.proofs.proof.nodes) or n > uint64(
        limits.native.limits.proof.nodes) or v > uint64(limits.proofs.proof.valueBytes) or v >
        uint64(limits.native.limits.proof.valueBytes): return LightStoreResult[PreparedData](
        status: LightStoreError.LimitExceeded) # Per-proof bounds precede node multiplication.
    if n > uint64(limits.proofs.batch.nodes)-nodes or v > uint64(
        limits.proofs.batch.valueBytes)-values or v > uint64(
        limits.proofs.view.valueBytes)-values: return LightStoreResult[PreparedData](
        status: LightStoreError.LimitExceeded) # Previously bounded totals make subtraction and later addition safe.
    if v > high(uint64)-41-n*64: return LightStoreResult[PreparedData](
        status: LightStoreError.LimitExceeded) # Prove one canonical record extent.
    let record = 41+n*64+v
    if record > high(uint64)-payload: return LightStoreResult[PreparedData](
        status: LightStoreError.LimitExceeded) # Prove cumulative payload arithmetic.
    payload += record
    nodes += n
    values += v
  let encoded = encodeLightHead(retained, limits.contextBytes)
  if encoded.error != LightHeadError.None: return LightStoreResult[PreparedData](
      status: LightStoreError.HeadFailure, headCause: encoded.error) # No raw-context fallback.
  let contextSize = uint64(encoded.value.len)+uint64(ContextPrefix+PagedManifestBytes)
  let geometry = initPagedHeader(limits.native.chain, retained.stateRoot, ManagedEpoch(1),
    LightDeltaSequence(0), count, payload, limits.native.limits.dataset, contextSize)
  if geometry.error != PagedCodecError.None: return LightStoreResult[PreparedData](
      status: LightStoreError.LimitExceeded) # Validate the complete worst-case native extent before namespace mutation.
  let available = uint64(limits.native.limits.workingBytes)
  let fixed = PagedStreamFixedBytes+256
  if available < fixed or contextSize > (available-fixed) div 4: return LightStoreResult[
      PreparedData](status: LightStoreError.LimitExceeded) # Reserve context transports before multiplication.
  let remaining = available-fixed-4*contextSize
  if count > remaining div (4'u64*31): return LightStoreResult[PreparedData](
      status: LightStoreError.LimitExceeded) # Inventory transport capacity is required for later startup too.
  let proofBytes = remaining-count*(4'u64*31)
  for index in 0..<view.len:
    # Each already bounded witness must fit alongside the reserved context and key transports.
    let proof = view.lookupAt(index).value.witness
    let nodeBytes = 2*uint64(proof.len)*64
    let valueBytes = uint64(proof.suppliedByteLength.value)
    if nodeBytes > proofBytes or valueBytes > (proofBytes-nodeBytes) div 2: return LightStoreResult[
        PreparedData](
        status: LightStoreError.LimitExceeded) # No largest-proof copy begins before full workspace preflight.
  LightStoreResult[PreparedData](status: LightStoreError.None,
    completed: PreparedData(head: retained, inner: encoded.value, count: count, payload: payload))
proc producer(prepared: PreparedData): PagedProducer =
  ## Repeated synchronous passes borrow one immutable view and materialize at most one detached native proof at a time.
  proc next(pass: int, ordinal: uint64, output: var nativecache.LightStateProof): PagedProducerStep {.closure.} =
    ## Host-extent proof follows the retained view's bounded length; no closure escapes native authoring.
    if ordinal >= prepared.count: return PagedProducerStep.End # Explicit stable end on every pass.
    let lookup = prepared.head.proofView.lookupAt(int(ordinal)).value
    let witness = lookup.witness
    var nodes = newSeq[EncodedStateNode](witness.len)
    for index in 0..<nodes.len: nodes[index] = witness.nodeAt(index).value # Fixed canonical node transport.
    output = nativecache.LightStateProof(key: lookup.key, proof: nativeproof.StateProof(
        nodes: nodes, value: witness.suppliedValue.value))
    PagedProducerStep.Item
  next
proc prepareLightProofMerge*(source: LightStorageSnapshot,
    batch: VerifiedStateProofBatch): LightStoreResult[PreparedLightPublication] =
  ## Passive preparation admits only independently verified same-root facts and retains exact expected source incarnation.
  let data = source.data
  if data == nil: return LightStoreResult[PreparedLightPublication](
      status: LightStoreError.NotReady) # Default snapshots grant no update authority.
  let merged = mergeLightProofs(data.head, batch, data.limits.head)
  if merged.error != LightHeadError.None: return LightStoreResult[PreparedLightPublication](
      status: LightStoreError.HeadFailure, headCause: merged.error) # Preserve original view on any failed merge.
  let target = prepare(merged.value, data.limits)
  if target.error != LightStoreError.None:
    # Preparation failures contain reasons only; no partially prepared target is exposed.
    if target.error == LightStoreError.HeadFailure: return LightStoreResult[
        PreparedLightPublication](status: LightStoreError.HeadFailure, headCause: target.headError)
    return LightStoreResult[PreparedLightPublication](status: target.error)
  LightStoreResult[PreparedLightPublication](status: LightStoreError.None,
      completed: PreparedLightPublication(source: data, target: target.value))
proc prepareLightHeadAdvance*(source: LightStorageSnapshot, trust: TrustedApplicationCheckpoint,
    evidence: ProofView): LightStoreResult[PreparedLightPublication] =
  ## Independent successor trust must satisfy the retained parent/hash/prior-root/profile contract before any disk work.
  let data = source.data
  if data == nil: return LightStoreResult[PreparedLightPublication](
      status: LightStoreError.NotReady) # No source history is inferred from native files.
  let advanced = advanceLightHead(data.head, trust, evidence, data.limits.head)
  if advanced.error != LightHeadError.None: return LightStoreResult[PreparedLightPublication](
      status: LightStoreError.HeadFailure, headCause: advanced.error) # Failed lineage checks preserve the source.
  let target = prepare(advanced.value, data.limits)
  if target.error != LightStoreError.None:
    # No incomplete target owner crosses the preparation boundary.
    if target.error == LightStoreError.HeadFailure: return LightStoreResult[
        PreparedLightPublication](status: LightStoreError.HeadFailure, headCause: target.headError)
    return LightStoreResult[PreparedLightPublication](status: target.error)
  LightStoreResult[PreparedLightPublication](status: LightStoreError.None,
      completed: PreparedLightPublication(source: data, target: target.value))
proc initializeLightPagedStore*(store: var LightPagedStore, path: string,
    head: LightApplicationHead, limits: LightPagedLimits): LightStoreResult[LightStorageSnapshot] =
  ## Exclusive bootstrap publishes one trusted metadata/partial-proof pair; no complete-state snapshot is allocated or retained.
  if store.opened: return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.Busy) # Unique ownership is never replaced in place.
  let prepared = prepare(head, limits)
  if prepared.error != LightStoreError.None:
    # Pure policy/header failure precedes namespace creation.
    if prepared.error == LightStoreError.HeadFailure: return LightStoreResult[LightStorageSnapshot](
        status: LightStoreError.HeadFailure, headCause: prepared.headError)
    return LightStoreResult[LightStorageSnapshot](status: prepared.error)
  if array[32, byte](head.stateRoot) != array[32, byte](
      limits.native.root): return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.TrustMismatch) # Caller-selected native root cannot replace trusted application authority.
  let context = envelope(prepared.value.inner, default(PagedManifest), limits).value
  var adopted = false
  defer:
    # Failed initialization retires every partially acquired native owner without repairing forensic files.
    if not adopted and store.opened:
      let retired = store.close
      if retired != FileError.None: result = LightStoreResult[LightStorageSnapshot](
          status: LightStoreError.FileFailure,
          fileCause: retired) # Native retirement uncertainty is explicit even after failed bootstrap.
  let created = initializePagedWriter(store.writer, path, limits.native, producer(prepared.value),
    prepared.value.count, prepared.value.payload, context)
  if created.error != PagedNativeError.None: return nativeFailed[LightStorageSnapshot,
      PagedPublication](created) # Native uncertainty remains exact and typed.
  if not created.value.writerUsable or created.value.retirementError !=
      FileError.None: return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.RecoveryRequired) # Known durable bytes still need fresh admission before facade adoption.
  let current = SnapshotData(head: prepared.value.head, selected: created.value.manifest,
      limits: limits)
  store.cache = StoreCache(current: current, healthy: true)
  adopted = true
  LightStoreResult[LightStorageSnapshot](status: LightStoreError.None,
      completed: LightStorageSnapshot(data: current))
proc openLightPagedStore*(store: var LightPagedStore, path: string,
    trust: TrustedApplicationCheckpoint,

limits: LightPagedLimits): LightStoreResult[LightStorageSnapshot] =
  ## Exact current trust and independently configured header geometry anchor all restored metadata and partial facts.
  if store.opened: return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.Busy) # Never replace a live writer lease.
  if not policyValid(limits): return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.PolicyMismatch) # No implicit V1/mode/backend fallback.
  let trusted = captureLightHead(trust, limits.head)
  if trusted.error != LightHeadError.None: return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.HeadFailure,
      headCause: trusted.error) # Header trust is checked before native namespace access.
  if array[32, byte](trusted.value.stateRoot) != array[32, byte](
      limits.native.root): return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.TrustMismatch) # Native selection must agree with independent trust.
  var reader = default(PagedReader)
  var adopted = false
  defer:
    # Readers never survive startup; a failed prefix also retires the writer lease.
    if reader.opened:
      let retired = reader.close
      if retired != FileError.None: result = LightStoreResult[LightStorageSnapshot](
          status: LightStoreError.FileFailure,
          fileCause: retired) # Failed startup cannot hide native reader retirement uncertainty.
    if not adopted and store.opened:
      let retired = store.close
      if retired != FileError.None: result = LightStoreResult[LightStorageSnapshot](
          status: LightStoreError.FileFailure,
          fileCause: retired) # Release the writer lease on every failed startup path.
  let opened = openPagedWriter(store.writer, path, limits.native)
  if opened.error != PagedNativeError.None: return nativeFailed[LightStorageSnapshot, bool](
      opened) # Normal open preserves all candidate forensic names.
  let selected = store.writer.selected
  if selected.error != PagedNativeError.None: return nativeFailed[LightStorageSnapshot,
      PagedManifest](selected) # Fresh exact CURRENT fencing precedes reader capture.
  let acquired = openPagedReader(reader, path, limits.native)
  if acquired.error != PagedNativeError.None: return nativeFailed[LightStorageSnapshot, bool](
      acquired) # The reader is an independent native pin.
  let actual = reader.selected
  if actual.error != PagedNativeError.None: return nativeFailed[LightStorageSnapshot,
      PagedManifest](actual) # Uncertainty cannot supply a usable source.
  if actual.value.bytes != selected.value.bytes: return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.StaleView) # Both owners must refer to the same exact physical artifact.
  let raw = reader.readContext(limits.native.limits.work)
  if raw.error != PagedNativeError.None: return nativeFailed[LightStorageSnapshot, PagedContext](
      raw) # Context and proof selection share one pin.
  let decoded = decodeContext(raw.value.bytes, selected.value, limits)
  if decoded.error != LightStoreError.None: return LightStoreResult[LightStorageSnapshot](
      status: decoded.error) # No context prefix becomes application state.
  let evidence = readAllPagedProofView(reader, trust.identity.stateRoot, limits.proofs,
      limits.inventory)
  if evidence.error != PagedProofViewError.None: return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.ViewFailure, viewCause: evidence) # Never expose a partially materialized view.
  let restored = restoreLightHead(decoded.value.inner, trust, evidence.value, limits.head,
      limits.contextBytes)
  if restored.error != LightHeadError.None: return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.HeadFailure, headCause: restored.error) # Disk bytes cannot mint current trust.
  let retired = reader.close
  if retired != FileError.None: return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.FileFailure,
      fileCause: retired) # Resource retirement must complete before adoption.
  let current = SnapshotData(head: restored.value, selected: selected.value, limits: limits)
  store.cache = StoreCache(current: current, previous: decoded.value.previous,
    healthy: true, pending: decoded.value.previous.initialized)
  adopted = true
  LightStoreResult[LightStorageSnapshot](status: LightStoreError.None,
      completed: LightStorageSnapshot(data: current))
proc commit*(store: var LightPagedStore, job: PreparedLightPublication): LightStoreResult[
    LightStorageSnapshot] =
  ## The excluded IO owner publishes the exact privately prepared source/target pair before passive cache adoption.
  let before = store.snapshot
  if before.error != LightStoreError.None: return LightStoreResult[LightStorageSnapshot](
      status: before.error) # Defaults and quarantine cannot mutate native state.
  let cache = store.cache
  assert cache != nil
  let source = job.source
  let target = job.target
  if source == nil or target == nil: return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.NotReady) # No forged default target is accepted.
  if source != before.value.data: return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.StaleView) # Foreign and stale snapshot incarnations cannot authorize this owner.
  if cache.pending: return LightStoreResult[LightStorageSnapshot](
      status: LightStoreError.RetirementPending) # One expected predecessor bounds unreclaimed physical artifacts.
  let selected = store.writer.selected
  if selected.error != PagedNativeError.None:
    store.quarantine() # Native uncertainty requires explicit close/reopen.
    return nativeFailed[LightStorageSnapshot, PagedManifest](selected)
  if selected.value.bytes != source.selected.bytes:
    store.quarantine() # Exact physical selection and passive source must agree.
    return LightStoreResult[LightStorageSnapshot](status: LightStoreError.StaleView)
  let context = envelope(target.inner, source.selected, source.limits).value
  var candidate = default(PagedCandidate)
  defer:
    # Failed authoring retains its forensic file, but no descriptor may leak from the operation.
    if candidate.opened:
      let retired = candidate.close
      if retired != FileError.None:
        store.quarantine() # Close uncertainty invalidates further application mutations.
        result = LightStoreResult[LightStorageSnapshot](status: LightStoreError.FileFailure,
            fileCause: retired)
  let authored = if array[32, byte](source.head.stateRoot) == array[32, byte](
      target.head.stateRoot):
    preparePagedReplacement(store.writer, candidate, producer(target), target.count, target.payload, context)
  else:
    preparePagedAdvance(store.writer, candidate, target.head.stateRoot, producer(target),
        target.count, target.payload,
        context) # Root change preserves ordinary sequence; native authoring still validates every proof.
  if authored.error != PagedNativeError.None:
    store.quarantine() # Explicit recovery, never a second automatic attempt, resolves a failed candidate.
    return nativeFailed[LightStorageSnapshot, StorageDurability](authored)
  let published = store.writer.publish(candidate)
  if published.error != PagedNativeError.None:
    store.quarantine() # A partially durable selection is resolved only by independently trusted startup.
    return nativeFailed[LightStorageSnapshot, PagedPublication](published)
  if not published.value.writerUsable or published.value.retirementError != FileError.None:
    store.quarantine() # Physical success alone cannot authorize a facade whose native owner became unusable.
    return LightStoreResult[LightStorageSnapshot](status: LightStoreError.RecoveryRequired)
  var limits = source.limits
  limits.native.root = target.head.stateRoot
  let current = SnapshotData(head: target.head, selected: published.value.manifest, limits: limits)
  cache.previous = source.selected
  cache.pending = true
  cache.current = current # Confirmed native success precedes target metadata/proof adoption.
  LightStoreResult[LightStorageSnapshot](status: LightStoreError.None,
      completed: LightStorageSnapshot(data: current))
proc prepareLightRetirement*(store: LightPagedStore): LightStoreResult[PreparedLightRetirement] =
  ## Passive job construction does no native IO and captures no reader pin.
  let selected = store.snapshot
  if selected.error != LightStoreError.None: return LightStoreResult[PreparedLightRetirement](
      status: selected.error) # Default/quarantined caches grant no cleanup job.
  let cache = store.cache
  assert cache != nil
  if not cache.pending: return LightStoreResult[PreparedLightRetirement](
      status: LightStoreError.NotReady) # No directory wildcard or inferred predecessor.
  LightStoreResult[PreparedLightRetirement](status: LightStoreError.None,
    completed: PreparedLightRetirement(owner: cache, current: selected.value.data,
        previous: cache.previous))
proc retire*(store: var LightPagedStore, job: PreparedLightRetirement): LightStoreResult[
    PagedReclamation] =
  ## A separate excluded operation confirms expected old-content absence without changing the adopted application head.
  let selected = store.snapshot
  if selected.error != LightStoreError.None: return LightStoreResult[PagedReclamation](
      status: selected.error) # Uncertain owners require fresh startup.
  let cache = store.cache
  assert cache != nil
  let expected = job.current
  if job.owner == nil or expected == nil or not job.previous.initialized: return LightStoreResult[
      PagedReclamation](status: LightStoreError.NotReady) # Default jobs have no deletion authority.
  if job.owner != cache or expected != selected.value.data or not cache.pending or
      job.previous.bytes != cache.previous.bytes: return LightStoreResult[PagedReclamation](
      status: LightStoreError.StaleView) # No stale/foreign job may dispatch native calls.
  let retired = store.writer.reclaimExpectedEpoch(job.previous, expected.selected)
  if retired.error != PagedNativeError.None:
    # A foreign reader's Busy refusal retains retryable bounded backpressure; other uncertainty quarantines mutations.
    if retired.error != PagedNativeError.FileFailure or retired.fileError !=
        FileError.Busy: store.quarantine()
    return nativeFailed[PagedReclamation, PagedReclamation](retired)
  if retired.value.retirementError != FileError.None:
    store.quarantine() # Confirmed unlink durability remains distinct from final handle retirement uncertainty.
    return LightStoreResult[PagedReclamation](status: LightStoreError.FileFailure,
        fileCause: retired.value.retirementError)
  cache.pending = false
  cache.previous = default(PagedManifest)
  LightStoreResult[PagedReclamation](status: LightStoreError.None, completed: retired.value)
proc synchronize*(store: var LightPagedStore): LightStoreResult[StorageDurability] =
  ## Real native barriers run only on the excluded owner, never from passive cache accessors.
  let selected = store.snapshot
  if selected.error != LightStoreError.None: return LightStoreResult[StorageDurability](
      status: selected.error) # No cached receipt can make an uncertain writer usable.
  let confirmed = store.writer.synchronize
  if confirmed.error != PagedNativeError.None:
    store.quarantine() # A failed fresh barrier requires independent reopen.
    return nativeFailed[StorageDurability, StorageDurability](confirmed)
  LightStoreResult[StorageDurability](status: LightStoreError.None, completed: confirmed.value)

func ready*(job: PreparedLightPublication): bool =
  ## Passive worker admission distinguishes a fully prepared immutable target/source pair from default jobs.
  job.source != nil and job.target != nil
func ready*(job: PreparedLightRetirement): bool =
  ## A queued cleanup job must retain its exact cache incarnation, current selection and expected predecessor.
  job.owner != nil and job.current != nil and job.previous.initialized
