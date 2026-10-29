# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Synchronous bounded paged-light construction, complete admission and authenticated disk-search algorithms.
## Callbacks are borrowed only during each call. Checked metadata owns no file, pin, callback or resident index.
import std/assertions
import ./codec as paged_codec
import ../state_proof
import ../light/state_cache as light_state_cache
import ../../codec/bounded
import ../../codec/state/[layout as state_layout, trie as state_trie]
import ../../crypto/primitives

const PagedStreamFixedBytes* = 32768'u64 ## Conservative logical fixed-workspace reservation; not native RSS.
type
  PagedRead* = proc(offset: PagedOffset, output: var openArray[byte]): bool {.closure.}
    ## True means the complete requested extent was copied; no callback or output view may escape.
  PagedExtent* = proc(output: var uint64): bool {.closure.}
    ## Obtain actual EOF; native wrappers must also validate held file identity and immutable ownership.
  PagedAppend* = proc(input: openArray[byte]): bool {.closure.}
    ## Append all bytes or return uncertainty; never seek, overwrite, retain input or retry a different source.
  PagedInput* = object ## Caller-owned synchronous byte source; no lifetime or durability authority is implied.
    read*: nil PagedRead
    extent*: nil PagedExtent
  PagedOutput* = object ## An initially empty append-only source; failures preserve its forensic prefix.
    source*: PagedInput
    append*: nil PagedAppend
  PagedProducerStep* {.pure.} = enum ## End is distinct from source failure and from one supplied proof.
    Failed, Item, End
  PagedProducer* = proc(pass: int, ordinal: uint64,
      output: var LightStateProof): PagedProducerStep {.closure.}
    ## Supply the same sorted canonical stream for passes zero/one; one proof stays stable during use.
  PagedWorkLimits* = object ## Independent finite operation ceilings; zero always means no such work.
    ioCalls*, producerCalls*, pageHashes*, proofs*, nodes*: ElementLimit
    readBytes*, writeBytes*, valueBytes*: ByteLimit
  PagedStreamLimits* = object ## Dataset, per-proof, working-space and operation budgets never imply each other.
    dataset*: PagedLimits
    proof*: StateProofLimits
    workingBytes*: ByteLimit
    contextBytes*: ByteLimit ## Zero selects V1; positive context policy requires V2 under this finite cap.
    cachePages*: ElementLimit
    work*: PagedWorkLimits
  PagedStreamError* {.pure.} = enum ## Missing evidence is never an IO/proof failure or authenticated absence.
    Uninitialized, None, InvalidFormat, LimitExceeded, LengthOverflow, WrongChain, WrongRoot,
    ChecksumMismatch, BackendFailure, ProofFailure, IOFailure, ProducerFailure, ChangedInput,
    UnknownKey, UnsupportedPolicy
  PagedStreamResult*[T] = object ## No failed/default alternative carries an admitted prefix, lookup or artifact.
    case status: PagedStreamError
    of None: completed: T
    of ProofFailure: proofCause: StateProofError
    else: discard
  PagedStreamCounts* = object ## Passive successful-call counters; failed operations grant no partial artifact.
    ready: bool
    calls, producers, hashes, proofs, nodes, read, written, values: uint64
  CheckedPagedArtifact* = object ## Complete root-bound byte validation only; never a sealed native artifact/reader.
    ready: bool
    selected: PagedManifest
    header: PagedHeader
    policy: PagedStreamLimits
    used: PagedStreamCounts
    stream: PagedDigest
    contextRoot: PagedDigest
  PagedContext* = object ## Private opaque context is bound to its exact immutable light selection, never a complete-map snapshot.
    ready: bool
    selected: PagedManifest
    payload: seq[byte]
    used: PagedStreamCounts
  PagedQueryInventory* = object ## Detached authenticated query identities describe partial evidence, never a complete mapping or native pin.
    ready: bool
    selected: PagedManifest
    queries: seq[StateKey]
    used: PagedStreamCounts
  LoadedProof = object ## Private verified/raw pair exists only while one bounded proof is being decoded or selected.
    checked: VerifiedStateLookup
    record: LightStateProof
  LocatedProof = object ## Private selection carries actual lookup work until the public result chooses one owned representation.
    loaded: LoadedProof
    used: PagedStreamCounts
  PagedProofLookup* = object ## Owned immutable raw proof capture has no native resource or fabricated state-layer authority.
    ready: bool
    record: LightStateProof
    used: PagedStreamCounts
  PagedLookup* = object ## Independent owned proof result survives the source callback and checked metadata.
    ready: bool
    checked: VerifiedStateLookup
    used: PagedStreamCounts
  Work = object ## First-error operation state owns only fixed counters and policies.
    status: PagedStreamError
    proofCause: StateProofError
    limits: PagedStreamLimits
    used: PagedStreamCounts
    contextRoot: PagedDigest
  PageCache = object ## One fixed page slot; zero-cache mode uses the same finite transient IO buffer.
    valid: bool
    ordinal: uint64
    bytes: array[PagedPageBytes, byte]
  TreeMode {.pure.} = enum ## Both construction and full checking visit the identical canonical postorder stream.
    Append, Check

func error*[T](outcome: PagedStreamResult[T]): PagedStreamError =
  ## Inspect only the selected refusal reason.
  outcome.status
func value*[T](outcome: PagedStreamResult[T]): T {.inline,
    requires: outcome.status == PagedStreamError.None.} =
  ## A complete success is required before any result payload access.
  outcome.completed
func proofError*[T](outcome: PagedStreamResult[T]): StateProofError {.requires:
    outcome.status == PagedStreamError.ProofFailure.} =
  ## Preserve only the selected proof cause, never an inactive failure field.
  outcome.proofCause
func initialized*(artifact: CheckedPagedArtifact): bool =
  ## Default metadata has no complete-admission authority.
  artifact.ready
func manifest*(artifact: CheckedPagedArtifact): PagedManifest {.requires: artifact.ready.} =
  ## Return local byte selection metadata without native publication authority.
  artifact.selected
func header*(artifact: CheckedPagedArtifact): PagedHeader {.requires: artifact.ready.} =
  ## Return the exact checked root/chain/count/physical-position binding.
  artifact.header
func counts*(artifact: CheckedPagedArtifact): PagedStreamCounts {.requires: artifact.ready.} =
  ## Report actual successful operation counts, with proof-node/value work separate from local page hashing.
  artifact.used
func verified*(lookup: PagedLookup): VerifiedStateLookup {.requires: lookup.ready.} =
  ## Retain independently owned authenticated presence/absence after synchronous IO ends.
  lookup.checked
func counts*(lookup: PagedLookup): PagedStreamCounts {.requires: lookup.ready.} =
  ## Inspect successful lookup work without retaining any source callbacks.
  lookup.used
func ioCalls*(counts: PagedStreamCounts): uint64 {.requires: counts.ready.} =
  ## Include actual extent queries, exact reads and append attempts.
  counts.calls
func producerCalls*(counts: PagedStreamCounts): uint64 {.requires: counts.ready.} =
  ## Count requested items and explicit end markers in both producer passes.
  counts.producers
func pageHashes*(counts: PagedStreamCounts): uint64 {.requires: counts.ready.} =
  ## Count local page/tree/stream-binding hash invocations, excluding separately bounded proof cryptography.
  counts.hashes
func proofs*(counts: PagedStreamCounts): uint64 {.requires: counts.ready.} =
  ## Count complete proof-verifier invocations.
  counts.proofs
func nodes*(counts: PagedStreamCounts): uint64 {.requires: counts.ready.} =
  ## Count submitted proof nodes independently of local layout hashes.
  counts.nodes
func readBytes*(counts: PagedStreamCounts): uint64 {.requires: counts.ready.} =
  ## Count exact callback input extents, including digest-path traffic.
  counts.read
func writeBytes*(counts: PagedStreamCounts): uint64 {.requires: counts.ready.} =
  ## Count append extents; no rewrite or sparse reservation exists in this engine.
  counts.written
func valueBytes*(counts: PagedStreamCounts): uint64 {.requires: counts.ready.} =
  ## Count raw value bytes submitted for proof verification across all passes.
  counts.values
proc fail(work: var Work, reason: PagedStreamError) =
  ## Preserve the first refusal even during later no-op cleanup/control flow.
  if work.status == PagedStreamError.None: work.status = reason
func refused[T](work: Work): PagedStreamResult[T] =
  ## Selected proof failures retain only their typed cause; all other failures contain only a reason.
  if work.status == PagedStreamError.ProofFailure:
    return PagedStreamResult[T](status: PagedStreamError.ProofFailure, proofCause: work.proofCause)
  PagedStreamResult[T](status: work.status)
func codecReason(reason: PagedCodecError): PagedStreamError =
  ## Keep format/identity/provider distinctions without exposing codec success payloads after failure.
  case reason
  of PagedCodecError.Uninitialized: PagedStreamError.Uninitialized
  of PagedCodecError.None: PagedStreamError.None
  of PagedCodecError.InvalidFormat: PagedStreamError.InvalidFormat
  of PagedCodecError.LimitExceeded: PagedStreamError.LimitExceeded
  of PagedCodecError.LengthOverflow: PagedStreamError.LengthOverflow
  of PagedCodecError.WrongChain: PagedStreamError.WrongChain
  of PagedCodecError.WrongRoot: PagedStreamError.WrongRoot
  of PagedCodecError.ChecksumMismatch: PagedStreamError.ChecksumMismatch
  of PagedCodecError.BackendFailure: PagedStreamError.BackendFailure
type CounterKind {.pure.} = enum ## Private work channels prevent aliasing the aggregate owner and one of its fields.
  IOCall, ProducerCall, PageHash, Proof, ProofNode, ReadByte, WriteByte, ValueByte
proc increment(used: var uint64, amount, maximum: uint64): bool =
  ## Prove each quota addition before evaluating it; immutable ceilings are detached from mutable counters.
  if used > maximum or amount > maximum-used: return false
  used += amount
  true
proc charge(work: var Work, kind: CounterKind, amount: uint64): bool =
  ## A named channel keeps mutation in one owner and preserves first-error behavior without aliased parameters.
  if work.status != PagedStreamError.None: return false
  let limits = work.limits.work
  let admitted = case kind
    of CounterKind.IOCall: increment(work.used.calls, amount, uint64(limits.ioCalls))
    of CounterKind.ProducerCall: increment(work.used.producers, amount, uint64(
        limits.producerCalls))
    of CounterKind.PageHash: increment(work.used.hashes, amount, uint64(limits.pageHashes))
    of CounterKind.Proof: increment(work.used.proofs, amount, uint64(limits.proofs))
    of CounterKind.ProofNode: increment(work.used.nodes, amount, uint64(limits.nodes))
    of CounterKind.ReadByte: increment(work.used.read, amount, uint64(limits.readBytes))
    of CounterKind.WriteByte: increment(work.used.written, amount, uint64(limits.writeBytes))
    of CounterKind.ValueByte: increment(work.used.values, amount, uint64(limits.valueBytes))
  if not admitted: work.fail(PagedStreamError.LimitExceeded)
  admitted
func validatePagedContextSize*(size: uint64, limit: ByteLimit): PagedStreamError =
  ## Explicit physical context presence is separate from proof, dataset and working-space budgets.
  if (size == 0) != (uint64(limit) == 0): return PagedStreamError.UnsupportedPolicy # No V1/V2 fallback.
  if size > uint64(limit): return PagedStreamError.LimitExceeded # Check the independent opaque context ceiling.
  PagedStreamError.None
func initWork(limits: PagedStreamLimits): Work =
  ## Reserve fixed scratch before callbacks; this first buffered engine supports exactly zero or one cache slot.
  result = Work(status: PagedStreamError.None, limits: limits, used: PagedStreamCounts(ready: true))
  if uint64(limits.workingBytes) < PagedStreamFixedBytes+41:
    result.status = PagedStreamError.LimitExceeded
  elif uint64(limits.cachePages) > 1:
    result.status = PagedStreamError.UnsupportedPolicy
proc readExact(io: PagedInput, offset: uint64, output: var openArray[byte], work: var Work): bool =
  ## All-or-failure borrowed reads are charged before dispatch; the callback retains neither view nor output.
  if work.status != PagedStreamError.None: return false
  let callback = io.read
  if callback == nil:
    work.fail(PagedStreamError.Uninitialized)
    return false
  if not work.charge(CounterKind.IOCall, 1): return false
  if not work.charge(CounterKind.ReadByte, uint64(output.len)): return false
  if not callback(PagedOffset(offset), output):
    work.fail(PagedStreamError.IOFailure)
    return false
  true
proc checkExtent(io: PagedInput, expected: uint64, work: var Work): bool =
  ## Check actual EOF before and after successful validation/lookup; native identity is the wrapper's duty.
  if work.status != PagedStreamError.None: return false
  let callback = io.extent
  if callback == nil:
    work.fail(PagedStreamError.Uninitialized)
    return false
  if not work.charge(CounterKind.IOCall, 1): return false
  var actual = 0'u64
  if not callback(actual): work.fail(PagedStreamError.IOFailure)
  elif actual != expected: work.fail(PagedStreamError.ChangedInput)
  work.status == PagedStreamError.None
proc appendExact(io: PagedOutput, bytes: openArray[byte], work: var Work): bool =
  ## Append only canonical prefixes; uncertain writes never yield a completed artifact or get rolled back.
  if work.status != PagedStreamError.None: return false
  let callback = io.append
  if callback == nil:
    work.fail(PagedStreamError.Uninitialized)
    return false
  if not work.charge(CounterKind.IOCall, 1): return false
  if not work.charge(CounterKind.WriteByte, uint64(bytes.len)): return false
  if not callback(bytes):
    work.fail(PagedStreamError.IOFailure)
    return false
  true
proc hashBudget(work: var Work, count = 1'u64): bool =
  ## Local layout hashes have their own explicit work channel, separate from proof nodes/value verification.
  work.charge(CounterKind.PageHash, count)
proc fetch(io: PagedInput, shape: PagedGeometry, root: PagedDigest, page: uint64,
    cache: var PageCache, work: var Work): bool =
  ## Never install unverified pages. Every miss authenticates to the captured complete tree root.
  if work.status != PagedStreamError.None: return false
  if cache.valid and cache.ordinal == page: return true
  cache.valid = false
  let planned = pagedPath(shape, PageOrdinal(page))
  if planned.error != PagedCodecError.None:
    work.fail(codecReason(planned.error))
    return false
  let path = planned.value
  if not work.hashBudget(uint64(path.len)+1): return false
  if not io.readExact(page*uint64(PagedPageBytes), cache.bytes, work): return false
  var siblings = default(array[64, PagedDigest])
  for level in 0..<path.len:
    # Checked path positions are inside the exact selected tree extent.
    var raw = default(array[32, byte])
    if not io.readExact(uint64(path.step(level).offset), raw, work): return false
    siblings[level] = PagedDigest(raw)
  let checked = if path.len == 0: verifyPagedPage(shape, PageOrdinal(page), cache.bytes, [], root)
    else: verifyPagedPage(shape, PageOrdinal(page), cache.bytes, siblings.toOpenArray(0,
        path.len-1), root)
  if checked != PagedCodecError.None:
    work.fail(codecReason(checked))
    return false
  cache.ordinal = page
  cache.valid = uint64(work.limits.cachePages) == 1
  true
proc authenticated(io: PagedInput, shape: PagedGeometry, root: PagedDigest, offset: uint64,
    output: var openArray[byte], cache: var PageCache, work: var Work): bool =
  ## Bounded page windows cover exact requested data bytes; no digest-tree bytes masquerade as payload.
  if work.status != PagedStreamError.None: return false
  let endData = uint64(shape.treeOffset)
  if offset > endData or uint64(output.len) > endData-offset:
    work.fail(PagedStreamError.InvalidFormat)
    return false
  var written = 0
  while written < output.len:
    # Whole-request containment proves each cursor addition and the remaining page fragment.
    let cursor = offset+uint64(written)
    let page = cursor div uint64(PagedPageBytes)
    let inside = int(cursor mod uint64(PagedPageBytes))
    let take = min(output.len-written, PagedPageBytes-inside)
    if not io.fetch(shape, root, page, cache, work): return false
    for index in 0..<take: output[written+index] = cache.bytes[inside+index]
    written += take
  true
proc proofExtent(proof: StateProof, work: var Work): uint64 =
  ## Bound transport plus simultaneous owned verified value before allocation, encoding or proof hashing.
  result = 0
  let nodes = uint64(proof.nodes.len)
  let values = uint64(proof.value.len)
  if nodes > 249 or nodes > uint64(work.limits.proof.nodes) or values > uint64(
      work.limits.proof.valueBytes):
    work.fail(PagedStreamError.LimitExceeded)
    return
  let fixed = PagedStreamFixedBytes+41+2*nodes*64
  let maximum = min(uint64(work.limits.workingBytes), uint64(high(int)))
  if fixed > maximum or values > (maximum-fixed) div 2:
    work.fail(PagedStreamError.LimitExceeded)
    return
  41+nodes*64+values
proc chargeProof(nodes, values: uint64, work: var Work): bool =
  ## Aggregate proof quotas precede proof buffer allocation and cryptographic work.
  if not work.charge(CounterKind.Proof, 1): return false
  if not work.charge(CounterKind.ProofNode, nodes): return false
  work.charge(CounterKind.ValueByte, values)
proc checkProof(root: StateRoot, key: StateKey, proof: StateProof,
    work: var Work): PagedStreamResult[VerifiedStateLookup] =
  ## Callers preflight memory/quotas before this verifier; temporary owners retire before the next proof.
  if work.status != PagedStreamError.None: return refused[VerifiedStateLookup](work)
  let checked = verifyStateProof(root, key, proof, work.limits.proof)
  case checked.error
  of StateProofError.None:
    return PagedStreamResult[VerifiedStateLookup](status: PagedStreamError.None,
        completed: checked.value)
  of StateProofError.BackendFailure: work.fail(PagedStreamError.BackendFailure)
  of StateProofError.LimitExceeded: work.fail(PagedStreamError.LimitExceeded)
  else:
    work.fail(PagedStreamError.ProofFailure)
    work.proofCause = checked.error
  refused[VerifiedStateLookup](work)
proc loadEvidence(io: PagedInput, header: PagedHeader, tree: PagedDigest, row: PagedDescriptor,
    cache: var PageCache, work: var Work): PagedStreamResult[LoadedProof] =
  ## Authenticate framing before allocation, then reconstruct and verify just one bounded proof/value.
  let shape = header.geometry
  let start = uint64(shape.payloadOffset)+uint64(row.offset)
  var prefix = default(array[41, byte])
  if not io.authenticated(shape, tree, start, prefix, cache, work): return refused[
      LoadedProof](work)
  let framed = decodePagedProofShape(prefix, row, work.limits.proof.nodes,
      work.limits.proof.valueBytes)
  if framed.error != PagedCodecError.None:
    work.fail(codecReason(framed.error))
    return refused[LoadedProof](work)
  let record = framed.value
  let fixed = PagedStreamFixedBytes+41+2*uint64(record.nodes)*64
  let maximum = min(uint64(work.limits.workingBytes), uint64(high(int)))
  if fixed > maximum or record.valueBytes > (maximum-fixed) div 2:
    work.fail(PagedStreamError.LimitExceeded)
    return refused[LoadedProof](work)
  if not chargeProof(uint64(record.nodes), record.valueBytes, work): return refused[
      LoadedProof](work)
  var proof = StateProof(nodes: newSeq[EncodedStateNode](record.nodes), value: newSeq[byte](int(
      record.valueBytes)))
  var cursor = start+41
  for index in 0..<record.nodes:
    # Framing checked the exact row extent, so every complete node remains inside its payload span.
    var raw = default(array[64, byte])
    if not io.authenticated(shape, tree, cursor, raw, cache, work): return refused[
        LoadedProof](work)
    proof.nodes[index] = EncodedStateNode(raw)
    cursor += 64
  if not io.authenticated(shape, tree, cursor, proof.value, cache, work): return refused[
      LoadedProof](work)
  let verified = checkProof(header.root, row.key, proof, work)
  if verified.error != PagedStreamError.None: return refused[LoadedProof](work)
  PagedStreamResult[LoadedProof](status: PagedStreamError.None,
    completed: LoadedProof(checked: verified.value, record: LightStateProof(key: row.key,
        proof: proof)))
proc loadProof(io: PagedInput, header: PagedHeader, tree: PagedDigest, row: PagedDescriptor,
    cache: var PageCache, work: var Work): PagedStreamResult[VerifiedStateLookup] =
  ## Ordinary admission retires raw evidence before allocating its separate canonical replay transport.
  let loaded = loadEvidence(io, header, tree, row, cache, work)
  if loaded.error != PagedStreamError.None: return refused[VerifiedStateLookup](work)
  PagedStreamResult[VerifiedStateLookup](status: PagedStreamError.None,
      completed: loaded.value.checked)
proc zeroRange(io: PagedInput, shape: PagedGeometry, tree: PagedDigest, start, stop: uint64,
    cache: var PageCache, work: var Work): bool =
  ## Padding has at most one logical page; every inspected byte must also authenticate to the captured root.
  if start > stop or stop-start >= uint64(PagedPageBytes):
    work.fail(PagedStreamError.InvalidFormat)
    return false
  var bytes = default(array[PagedPageBytes, byte])
  let size = int(stop-start)
  if size > 0:
    if not io.authenticated(shape, tree, start, bytes.toOpenArray(0, size-1), cache,
        work): return false
    for index in 0..<size:
      if bytes[index] != 0:
        work.fail(PagedStreamError.InvalidFormat)
        return false
  true
proc treeDigest(io: PagedOutput, mode: TreeMode, shape: PagedGeometry, slot: var uint64,
    digest: PagedDigest, work: var Work): bool =
  ## Visit every stored leaf/internal digest in canonical postorder without a resident tree.
  let slots = shape.treeLeaves+(shape.treeLeaves-1)
  if slot >= slots:
    work.fail(PagedStreamError.InvalidFormat)
    return false
  let raw = array[32, byte](digest)
  if mode == TreeMode.Append:
    if not io.appendExact(raw, work): return false
  else:
    var stored = default(array[32, byte])
    if not io.source.readExact(uint64(shape.treeOffset)+slot*32, stored, work): return false
    if stored != raw:
      work.fail(PagedStreamError.ChecksumMismatch)
      return false
  inc slot
  true
proc bindContext(previous, leaf: PagedDigest, work: var Work): PagedDigest =
  ## Constant-size context equality folds already authenticated physical leaf digests, independently of proof transport.
  const Domain = "RAGNAROK-LIGHT-PAGED-CONTEXT-V1\n"
  result = default(PagedDigest)
  if not work.hashBudget: return # First-error work refusal cannot expose a partially checked artifact.
  var raw = default(array[Domain.len+64, byte])
  for index, character in Domain: raw[index] = byte(character) # Local context-chain domain, not a JAM commitment.
  for index in 0..<32:
    # Ordered complete leaf identities already bind physical page ordinals and every context/padding byte.
    raw[Domain.len+index] = array[32, byte](previous)[index]
    raw[Domain.len+32+index] = array[32, byte](leaf)[index]
  let hashed = blake2b256(raw)
  if hashed.error != CryptoError.None: work.fail(PagedStreamError.BackendFailure) # Preserve provider refusal.
  else: result = PagedDigest(array[32, byte](hashed.value)) # Only complete hash success advances the equality fingerprint.
proc walkTree(io: PagedOutput, mode: TreeMode, shape: PagedGeometry,
    work: var Work): PagedStreamResult[PagedDigest] =
  ## A fixed carry stack emits/checks all postorder bytes and domain-separated padding leaves.
  if mode == TreeMode.Check: work.contextRoot = default(
      PagedDigest) # Admission owns a fresh context signature, separate from construction.
  var carry = default(array[64, PagedDigest])
  var page = default(array[PagedPageBytes, byte])
  var ordinal = 0'u64
  var slot = 0'u64
  var root = default(PagedDigest)
  while ordinal < shape.treeLeaves:
    # Only real leaves cause page IO; synthetic leaves have a distinct ordinal-bound domain.
    if not work.hashBudget: return refused[PagedDigest](work)
    var leaf = default(PagedCodecResult[PagedDigest])
    if ordinal < shape.dataPages:
      if not io.source.readExact(ordinal*uint64(PagedPageBytes), page, work): return refused[
          PagedDigest](work)
      leaf = pagedLeafDigest(shape, PageOrdinal(ordinal), page)
    else: leaf = pagedPaddingDigest(shape, PageOrdinal(ordinal))
    if leaf.error != PagedCodecError.None:
      work.fail(codecReason(leaf.error))
      return refused[PagedDigest](work)
    if mode == TreeMode.Check and shape.contextBytes > 0 and ordinal < shape.dataPages and
        ordinal >= uint64(shape.contextOffset) div uint64(PagedPageBytes):
      let previousContext = work.contextRoot # Capture the fixed digest before passing its owner mutably.
      work.contextRoot = bindContext(previousContext, leaf.value,
          work) # Reuse each real context leaf with no additional source read.
      if work.status != PagedStreamError.None: return refused[PagedDigest](work)
    var current = leaf.value
    if not io.treeDigest(mode, shape, slot, current, work): return refused[PagedDigest](work)
    var consumed = ordinal
    var level = 0
    while (consumed and 1) != 0:
      # A completed right subtree combines with its already emitted left subtree.
      if not work.hashBudget: return refused[PagedDigest](work)
      let parent = pagedNodeDigest(carry[level], current)
      if parent.error != PagedCodecError.None:
        work.fail(codecReason(parent.error))
        return refused[PagedDigest](work)
      current = parent.value
      if not io.treeDigest(mode, shape, slot, current, work): return refused[PagedDigest](work)
      consumed = consumed shr 1
      inc level
    carry[level] = current
    root = current
    inc ordinal
  PagedStreamResult[PagedDigest](status: PagedStreamError.None, completed: root)
proc bindRecord(previous: PagedDigest, bytes: openArray[byte], work: var Work): PagedDigest =
  ## Constant-size chained fingerprints bind the two canonical producer passes without retaining their records.
  result = default(PagedDigest)
  if not work.hashBudget(2): return
  let record = blake2b256(bytes)
  if record.error != CryptoError.None:
    work.fail(PagedStreamError.BackendFailure)
    return
  const Domain = "RAGNAROK-LIGHT-PAGED-STREAM-V1\n"
  var raw = default(array[Domain.len+64, byte])
  for index, c in Domain: raw[index] = byte(c)
  for index in 0..<32:
    raw[Domain.len+index] = array[32, byte](previous)[index]
    raw[Domain.len+32+index] = array[32, byte](record.value)[index]
  let combined = blake2b256(raw)
  if combined.error != CryptoError.None: work.fail(PagedStreamError.BackendFailure)
  else: result = PagedDigest(array[32, byte](combined.value))
proc inspect(io: PagedInput, selected: PagedManifest, work: var Work): PagedStreamResult[
    CheckedPagedArtifact] =
  ## Strict complete admission authenticates each proof scan byte, then checks every tree slot and actual EOF.
  if not selected.initialized:
    work.fail(PagedStreamError.Uninitialized)
    return refused[CheckedPagedArtifact](work)
  if selected.byteLength > uint64(work.limits.dataset.bytes) or selected.byteLength > uint64(high(int)):
    work.fail(PagedStreamError.LimitExceeded)
    return refused[CheckedPagedArtifact](work)
  if not io.checkExtent(selected.byteLength, work): return refused[CheckedPagedArtifact](work)
  var rawHeader = default(array[PagedPageBytes, byte])
  if not io.readExact(0, rawHeader, work): return refused[CheckedPagedArtifact](work)
  let decoded = decodePagedHeader(rawHeader, selected.chainId, selected.root, work.limits.dataset,
      work.limits.contextBytes)
  if decoded.error != PagedCodecError.None:
    work.fail(codecReason(decoded.error))
    return refused[CheckedPagedArtifact](work)
  let header = decoded.value
  let headerBinding = validatePagedBinding(selected, header)
  if headerBinding != PagedCodecError.None:
    work.fail(codecReason(headerBinding))
    return refused[CheckedPagedArtifact](work)
  let shape = header.geometry
  var cache = default(PageCache)
  if not io.fetch(shape, selected.pageRoot, 0, cache, work): return refused[CheckedPagedArtifact](work)
  if cache.bytes != rawHeader:
    work.fail(PagedStreamError.ChangedInput)
    return refused[CheckedPagedArtifact](work)
  var scan = initPagedIndexScan(shape)
  var binding = default(PagedDigest)
  var ordinal = 0'u64
  while ordinal < shape.entries:
    # Index search inventory stays on disk; one detached row/proof retires before the next iteration.
    var raw = default(array[PagedDescriptorBytes, byte])
    if not io.authenticated(shape, selected.pageRoot, 4096+ordinal*64, raw, cache,
        work): return refused[CheckedPagedArtifact](work)
    let admitted = scan.admit(raw)
    if admitted.error != PagedCodecError.None:
      work.fail(codecReason(admitted.error))
      return refused[CheckedPagedArtifact](work)
    block:
      # Retire transport and verified-value owners before the one-record stream-fingerprint buffer is allocated.
      let checked = loadProof(io, header, selected.pageRoot, admitted.value, cache, work)
      if checked.error != PagedStreamError.None: return refused[CheckedPagedArtifact](work)
    let row = admitted.value
    var transport = newSeq[byte](int(row.byteLength))
    let start = uint64(shape.payloadOffset)+uint64(row.offset)
    if not io.authenticated(shape, selected.pageRoot, start, transport, cache,
        work): return refused[CheckedPagedArtifact](work)
    binding = bindRecord(binding, transport, work)
    if work.status != PagedStreamError.None: return refused[CheckedPagedArtifact](work)
    inc ordinal
  let complete = scan.finish
  if complete != PagedCodecError.None:
    work.fail(codecReason(complete))
    return refused[CheckedPagedArtifact](work)
  if not io.zeroRange(shape, selected.pageRoot, 4096+shape.entries*64,
      uint64(shape.payloadOffset), cache, work): return refused[CheckedPagedArtifact](work)
  if not io.zeroRange(shape, selected.pageRoot, uint64(shape.payloadOffset)+shape.payloadBytes,
      uint64(shape.contextOffset), cache, work): return refused[CheckedPagedArtifact](work)
  if not io.zeroRange(shape, selected.pageRoot, uint64(shape.contextOffset)+shape.contextBytes,
      uint64(shape.treeOffset), cache, work): return refused[CheckedPagedArtifact](work)
  let checkedTree = walkTree(PagedOutput(source: io), TreeMode.Check, shape, work)
  if checkedTree.error != PagedStreamError.None: return refused[CheckedPagedArtifact](work)
  if array[32, byte](checkedTree.value) != array[32, byte](selected.pageRoot):
    work.fail(PagedStreamError.ChecksumMismatch)
    return refused[CheckedPagedArtifact](work)
  if not io.checkExtent(selected.byteLength, work): return refused[CheckedPagedArtifact](work)
  PagedStreamResult[CheckedPagedArtifact](status: PagedStreamError.None,
    completed: CheckedPagedArtifact(ready: true, selected: selected, header: header,
      policy: work.limits, used: work.used, stream: binding, contextRoot: work.contextRoot))
proc validatePagedArtifact*(io: PagedInput, selected: PagedManifest,
    limits: PagedStreamLimits): PagedStreamResult[CheckedPagedArtifact] =
  ## Borrow callbacks synchronously and return only complete metadata, never a native sealed owner or partial image.
  if not selected.initialized or io.read == nil or io.extent == nil:
    return PagedStreamResult[CheckedPagedArtifact](status: PagedStreamError.Uninitialized)
  var work = initWork(limits)
  if work.status != PagedStreamError.None: return refused[CheckedPagedArtifact](work)
  inspect(io, selected, work)
func compare(a, b: StateKey): int =
  ## Canonical full serialized-key ordering is shared by binary search and the producer contract.
  let left = array[31, byte](a)
  let right = array[31, byte](b)
  for index in 0..<31:
    if left[index] < right[index]: return -1
    if left[index] > right[index]: return 1
  0
proc locateProof(artifact: CheckedPagedArtifact, io: PagedInput, query: StateKey,
    budget: PagedWorkLimits): PagedStreamResult[LocatedProof] =
  ## Authenticate binary-search pages and one proof against captured roots, with actual EOF checked before success/UnknownKey.
  if not artifact.ready or io.read == nil or io.extent == nil:
    return PagedStreamResult[LocatedProof](status: PagedStreamError.Uninitialized)
  var policy = artifact.policy
  policy.work = budget
  var work = initWork(policy)
  if work.status != PagedStreamError.None: return refused[LocatedProof](work)
  let selected = artifact.selected
  let shape = artifact.header.geometry
  if not io.checkExtent(selected.byteLength, work): return refused[LocatedProof](work)
  var cache = default(PageCache)
  if not io.fetch(shape, selected.pageRoot, 0, cache, work): return refused[LocatedProof](work)
  let header = decodePagedHeader(cache.bytes, selected.chainId, selected.root, policy.dataset,
      policy.contextBytes)
  if header.error != PagedCodecError.None:
    work.fail(codecReason(header.error))
    return refused[LocatedProof](work)
  if header.value.bytes != artifact.header.bytes:
    work.fail(PagedStreamError.ChangedInput)
    return refused[LocatedProof](work)
  var first = 0'u64
  var stop = shape.entries
  while first < stop:
    # Difference-before-addition proves midpoint and fixed row addressing without resident descriptors.
    let middle = first+(stop-first) div 2
    var raw = default(array[PagedDescriptorBytes, byte])
    if not io.authenticated(shape, selected.pageRoot, 4096+middle*64, raw, cache,
        work): return refused[LocatedProof](work)
    let decoded = decodePagedDescriptor(raw, shape)
    if decoded.error != PagedCodecError.None:
      work.fail(codecReason(decoded.error))
      return refused[LocatedProof](work)
    let row = decoded.value
    let order = compare(query, row.key)
    if order == 0:
      let checked = loadEvidence(io, artifact.header, selected.pageRoot, row, cache, work)
      if checked.error != PagedStreamError.None: return refused[LocatedProof](work)
      if not io.checkExtent(selected.byteLength, work): return refused[LocatedProof](work)
      return PagedStreamResult[LocatedProof](status: PagedStreamError.None,
        completed: LocatedProof(loaded: checked.value, used: work.used))
    elif order < 0: stop = middle
    else: first = middle+1
  if not io.checkExtent(selected.byteLength, work): return refused[LocatedProof](work)
  work.fail(PagedStreamError.UnknownKey)
  refused[LocatedProof](work)
func failed[T, U](outcome: PagedStreamResult[U]): PagedStreamResult[T] {.requires:
    outcome.status != PagedStreamError.None.} =
  ## Changing successful representation preserves only the selected failure and optional proof cause.
  if outcome.status == PagedStreamError.ProofFailure:
    return PagedStreamResult[T](status: PagedStreamError.ProofFailure,
        proofCause: outcome.proofCause)
  PagedStreamResult[T](status: outcome.status)
proc lookupPaged*(artifact: CheckedPagedArtifact, io: PagedInput, query: StateKey,
    budget: PagedWorkLimits): PagedStreamResult[PagedLookup] =
  ## Ordinary lookups retain only verified values; unused raw proof bytes retire before returning.
  let located = locateProof(artifact, io, query, budget)
  if located.error != PagedStreamError.None: return failed[PagedLookup, LocatedProof](located)
  PagedStreamResult[PagedLookup](status: PagedStreamError.None,
    completed: PagedLookup(ready: true, checked: located.value.loaded.checked,
        used: located.value.used))
proc lookupPagedProof*(artifact: CheckedPagedArtifact, io: PagedInput, query: StateKey,
    budget: PagedWorkLimits): PagedStreamResult[PagedProofLookup] =
  ## Capture raw evidence only after the identical authenticated/verified lookup and final EOF checks.
  let located = locateProof(artifact, io, query, budget)
  if located.error != PagedStreamError.None: return failed[PagedProofLookup, LocatedProof](located)
  PagedStreamResult[PagedProofLookup](status: PagedStreamError.None,
    completed: PagedProofLookup(ready: true, record: located.value.loaded.record,
        used: located.value.used))
proc proof*(captured: PagedProofLookup): LightStateProof {.requires: captured.ready.} =
  ## Detach mutable transport while respecting the existing two-node-array/two-value workspace reservation.
  var nodes = newSeq[EncodedStateNode](captured.record.proof.nodes.len)
  var value = newSeq[byte](captured.record.proof.value.len)
  for index in 0..<nodes.len: nodes[index] = captured.record.proof.nodes[index] # Fixed canonical node copies.
  for index in 0..<value.len: value[index] = captured.record.proof.value[index] # No private mutable bytes escape.
  LightStateProof(key: captured.record.key, proof: StateProof(nodes: nodes, value: value))
func counts*(captured: PagedProofLookup): PagedStreamCounts {.requires: captured.ready.} =
  ## Report successful proof extraction work without retaining source IO or native lifetime.
  captured.used
proc put(output: var seq[byte], offset: int, number: uint64, width = 8) =
  ## One-proof preflight proves every fixed numeric write and complete detached transport extent.
  for index in 0..<width: output[offset+index] = byte((number shr (8*index)) and 255)
proc encode(record: LightStateProof, size: uint64): seq[byte] =
  ## At most one bounded proof transport exists, after its temporary verified lookup has retired.
  result = newSeq[byte](int(size))
  let key = array[31, byte](record.key)
  for index in 0..<31: result[index] = key[index]
  put(result, 31, uint64(record.proof.nodes.len), 2)
  put(result, 33, uint64(record.proof.value.len))
  var cursor = 41
  for node in record.proof.nodes:
    # Proof-node count and encoded extent were checked before this canonical copy.
    let raw = array[64, byte](node)
    for index in 0..<64: result[cursor+index] = raw[index]
    cursor += 64
  for index, octet in record.proof.value: result[cursor+index] = octet
proc next(producer: PagedProducer, pass: int, ordinal: uint64, output: var LightStateProof,
    work: var Work): PagedProducerStep =
  ## Explicit end markers and producer failures cannot be mistaken for successful empty proofs.
  result = PagedProducerStep.Failed
  if not work.charge(CounterKind.ProducerCall, 1): return
  result = producer(pass, ordinal, output)
  if result == PagedProducerStep.Failed: work.fail(PagedStreamError.ProducerFailure)
proc producerPass(io: PagedOutput, producer: PagedProducer, pass: int, header: PagedHeader,
    work: var Work): PagedDigest =
  ## Verify and fingerprint strictly sorted replayable evidence; index precedes payload with no whole-batch staging.
  result = default(PagedDigest)
  let shape = header.geometry
  var scan = initPagedIndexScan(shape)
  var ordinal = 0'u64
  var offset = 0'u64
  while ordinal < shape.entries:
    # One borrowed/owned proof input and one encoded record retire on each iteration.
    var record = default(LightStateProof)
    let step = producer.next(pass, ordinal, record, work)
    if work.status != PagedStreamError.None: return
    if step != PagedProducerStep.Item:
      work.fail(PagedStreamError.InvalidFormat)
      return
    let size = proofExtent(record.proof, work)
    if work.status != PagedStreamError.None: return
    let row = initPagedDescriptor(shape, record.key, PagedOffset(offset), size)
    if row.error != PagedCodecError.None:
      work.fail(codecReason(row.error))
      return
    let admitted = scan.admit(row.value.bytes)
    if admitted.error != PagedCodecError.None:
      work.fail(codecReason(admitted.error))
      return
    if not chargeProof(uint64(record.proof.nodes.len), uint64(record.proof.value.len), work): return
    block:
      # The successful verifier owner is destroyed before allocating encoded transport.
      let checked = checkProof(header.root, record.key, record.proof, work)
      if checked.error != PagedStreamError.None: return
    let encoded = encode(record, size)
    result = bindRecord(result, encoded, work)
    if work.status != PagedStreamError.None: return
    if pass == 0:
      if not io.appendExact(row.value.bytes, work): return
    else:
      if not io.appendExact(encoded, work): return
    offset += size
    inc ordinal
  var endRecord = default(LightStateProof)
  let ended = producer.next(pass, ordinal, endRecord, work)
  if work.status != PagedStreamError.None: return
  if ended != PagedProducerStep.End:
    work.fail(PagedStreamError.InvalidFormat)
    return
  let finished = scan.finish
  if finished != PagedCodecError.None: work.fail(codecReason(finished))
proc padding(io: PagedOutput, extent: uint64, work: var Work): bool =
  ## Append only the final canonical zero fragment of an index/payload page, never reserve sparse space.
  let size = int((4096-extent mod 4096) mod 4096)
  var zeros = default(array[PagedPageBytes, byte])
  if size == 0: return true
  io.appendExact(zeros.toOpenArray(0, size-1), work)
proc buildPagedArtifact*(io: PagedOutput, producer: nil PagedProducer, header: PagedHeader,
    limits: PagedStreamLimits, context: openArray[byte] = []): PagedStreamResult[
        CheckedPagedArtifact] =
  ## Append a replay-bound complete artifact, then strictly reverify it; synchronization/sealing/publication are separate.
  if producer == nil:
    return PagedStreamResult[CheckedPagedArtifact](status: PagedStreamError.Uninitialized)
  if not header.initialized or io.append == nil or io.source.read == nil or io.source.extent == nil:
    return PagedStreamResult[CheckedPagedArtifact](status: PagedStreamError.Uninitialized)
  var work = initWork(limits)
  if work.status != PagedStreamError.None: return refused[CheckedPagedArtifact](work)
  let shape = header.geometry
  let contextPolicy = validatePagedContextSize(shape.contextBytes, limits.contextBytes)
  if contextPolicy != PagedStreamError.None:
    work.fail(contextPolicy) # Physical format and opaque-byte admission precede producer or IO dispatch.
    return refused[CheckedPagedArtifact](work)
  if uint64(context.len) != shape.contextBytes:
    work.fail(PagedStreamError.InvalidFormat) # Exact stable borrowed context is mandatory; zero fill cannot substitute.
    return refused[CheckedPagedArtifact](work)
  let permitted = pagedGeometry(shape.entries, shape.payloadBytes, limits.dataset,
      shape.contextBytes)
  if permitted.error != PagedCodecError.None:
    work.fail(codecReason(permitted.error))
    return refused[CheckedPagedArtifact](work)
  if shape.byteLength > uint64(limits.work.writeBytes):
    work.fail(PagedStreamError.LimitExceeded)
    return refused[CheckedPagedArtifact](work)
  if not io.source.checkExtent(0, work): return refused[CheckedPagedArtifact](work)
  if not io.appendExact(header.bytes, work): return refused[CheckedPagedArtifact](work)
  let indexBinding = producerPass(io, producer, 0, header, work)
  if work.status != PagedStreamError.None: return refused[CheckedPagedArtifact](work)
  if not io.padding(shape.entries*64, work): return refused[CheckedPagedArtifact](work)
  let payloadBinding = producerPass(io, producer, 1, header, work)
  if work.status != PagedStreamError.None: return refused[CheckedPagedArtifact](work)
  if array[32, byte](indexBinding) != array[32, byte](payloadBinding):
    work.fail(PagedStreamError.ChangedInput)
    return refused[CheckedPagedArtifact](work)
  if not io.padding(shape.payloadBytes, work): return refused[CheckedPagedArtifact](work)
  if shape.contextBytes > 0:
    # V2 alone appends opaque context pages before the tree; V1 retains its existing IO schedule.
    if not io.source.checkExtent(uint64(shape.contextOffset), work): return refused[
        CheckedPagedArtifact](work)
    if not io.appendExact(context, work): return refused[CheckedPagedArtifact](work)
    if not io.padding(shape.contextBytes, work): return refused[CheckedPagedArtifact](work)
  if not io.source.checkExtent(uint64(shape.treeOffset), work): return refused[
      CheckedPagedArtifact](work)
  let tree = walkTree(io, TreeMode.Append, shape, work)
  if tree.error != PagedStreamError.None: return refused[CheckedPagedArtifact](work)
  if not work.hashBudget: return refused[CheckedPagedArtifact](work)
  let selected = encodePagedManifest(header, tree.value, ByteLimit(PagedManifestBytes))
  if selected.error != PagedCodecError.None:
    work.fail(codecReason(selected.error))
    return refused[CheckedPagedArtifact](work)
  let checked = inspect(io.source, selected.value, work)
  if checked.error != PagedStreamError.None: return checked
  if array[32, byte](checked.value.stream) != array[32, byte](indexBinding):
    work.fail(PagedStreamError.ChangedInput)
    return refused[CheckedPagedArtifact](work)
  checked

proc compactPagedArtifact*(io: PagedOutput, source: PagedInput, artifact: CheckedPagedArtifact,
    target: PagedHeader): PagedStreamResult[CheckedPagedArtifact] =
  ## Rewrite one pinned checked source through bounded authenticated pages, preserving exact knowledge and ordinary sequence.
  if not artifact.ready or not target.initialized or source.read == nil or source.extent == nil or
      io.source.read == nil or io.source.extent == nil or io.append == nil:
    return PagedStreamResult[CheckedPagedArtifact](status: PagedStreamError.Uninitialized)
  let original = artifact.header
  let shape = original.geometry
  let next = target.geometry
  if uint64(original.epoch) == high(uint64):
    return PagedStreamResult[CheckedPagedArtifact](status: PagedStreamError.LengthOverflow)
  let identities = array[32, byte](target.chainId) == array[32, byte](original.chainId) and
    array[32, byte](target.root) == array[32, byte](original.root)
  let counters = uint64(target.epoch) == uint64(original.epoch)+1 and
    uint64(target.sequence) == uint64(original.sequence)
  let geometry = next.entries == shape.entries and next.payloadBytes == shape.payloadBytes and
    next.contextBytes == shape.contextBytes
  if not identities or not counters or not geometry:
    return PagedStreamResult[CheckedPagedArtifact](status: PagedStreamError.ChangedInput)
  var work = initWork(artifact.policy)
  if work.status != PagedStreamError.None: return refused[CheckedPagedArtifact](work)
  if shape.byteLength > uint64(work.limits.work.writeBytes):
    work.fail(PagedStreamError.LimitExceeded)
    return refused[CheckedPagedArtifact](work)
  if not source.checkExtent(shape.byteLength, work): return refused[CheckedPagedArtifact](work)
  if not io.source.checkExtent(0, work): return refused[CheckedPagedArtifact](work)
  block:
    # Source page zero must still match the captured complete header before any append.
    var cache = default(PageCache)
    if not source.fetch(shape, artifact.selected.pageRoot, 0, cache, work): return refused[
        CheckedPagedArtifact](work)
    if cache.bytes != original.bytes:
      work.fail(PagedStreamError.ChangedInput)
      return refused[CheckedPagedArtifact](work)
    if not io.appendExact(target.bytes, work): return refused[CheckedPagedArtifact](work)
    var page = 1'u64
    while page < shape.dataPages:
      # Exact index/payload pages, including canonical padding, survive with no decoded batch or sort.
      if not source.fetch(shape, artifact.selected.pageRoot, page, cache, work): return refused[
          CheckedPagedArtifact](work)
      if not io.appendExact(cache.bytes, work): return refused[CheckedPagedArtifact](work)
      inc page
  if not source.checkExtent(shape.byteLength, work): return refused[CheckedPagedArtifact](work)
  if not io.source.checkExtent(uint64(shape.treeOffset), work): return refused[
      CheckedPagedArtifact](work)
  let tree = walkTree(io, TreeMode.Append, next, work)
  if tree.error != PagedStreamError.None: return refused[CheckedPagedArtifact](work)
  if not work.hashBudget: return refused[CheckedPagedArtifact](work)
  let selected = encodePagedManifest(target, tree.value, ByteLimit(PagedManifestBytes))
  if selected.error != PagedCodecError.None:
    work.fail(codecReason(selected.error))
    return refused[CheckedPagedArtifact](work)
  let checked = inspect(io.source, selected.value, work)
  if checked.error != PagedStreamError.None: return checked
  if array[32, byte](checked.value.stream) != array[32, byte](artifact.stream):
    work.fail(PagedStreamError.ChangedInput)
    return refused[CheckedPagedArtifact](work)
  checked

func samePagedKnowledge*(a, b: CheckedPagedArtifact): bool =
  ## Passive fully admitted artifacts agree on exact canonical evidence and opaque context under one root.
  a.ready and b.ready and array[32, byte](a.header.chainId) == array[32, byte](b.header.chainId) and
    array[32, byte](a.header.root) == array[32, byte](b.header.root) and
    a.header.geometry.entries == b.header.geometry.entries and
    a.header.geometry.payloadBytes == b.header.geometry.payloadBytes and
    a.header.geometry.contextBytes == b.header.geometry.contextBytes and
    array[32, byte](a.stream) == array[32, byte](b.stream) and
    array[32, byte](a.contextRoot) == array[32, byte](b.contextRoot)

func initialized*(context: PagedContext): bool =
  ## A default owner grants no authenticated opaque light context.
  context.ready
func manifest*(context: PagedContext): PagedManifest {.requires: context.ready.} =
  ## Bind retained context to the exact admitted physical selection, not merely its JAM root.
  context.selected
func byteLength*(context: PagedContext): int {.requires: context.ready.} =
  ## Scalar length allows application preflight without exposing mutable private backing.
  context.payload.len
proc bytes*(context: PagedContext): seq[byte] {.requires: context.ready.} =
  ## Return detached mutable transport while retaining no native descriptor, pin or callback.
  result = newSeq[byte](context.payload.len)
  for index in 0..<result.len: result[index] = context.payload[
      index] # Every output octet owns its independent backing.
func counts*(context: PagedContext): PagedStreamCounts {.requires: context.ready.} =
  ## Only complete success exposes passive successful work counters.
  context.used
proc contextBudget(inherited, requested: PagedWorkLimits): PagedWorkLimits =
  ## Per-call context work can only tighten every captured admission channel.
  PagedWorkLimits(ioCalls: ElementLimit(min(uint64(inherited.ioCalls), uint64(requested.ioCalls))),
    producerCalls: ElementLimit(min(uint64(inherited.producerCalls), uint64(
        requested.producerCalls))),
    pageHashes: ElementLimit(min(uint64(inherited.pageHashes), uint64(requested.pageHashes))),
    proofs: ElementLimit(min(uint64(inherited.proofs), uint64(requested.proofs))),
    nodes: ElementLimit(min(uint64(inherited.nodes), uint64(requested.nodes))),
    readBytes: ByteLimit(min(uint64(inherited.readBytes), uint64(requested.readBytes))),
    writeBytes: ByteLimit(min(uint64(inherited.writeBytes), uint64(requested.writeBytes))),
    valueBytes: ByteLimit(min(uint64(inherited.valueBytes), uint64(requested.valueBytes))))
proc readPagedContext*(io: PagedInput, checked: CheckedPagedArtifact,
    budget: PagedWorkLimits): PagedStreamResult[PagedContext] =
  ## Authenticate one opaque context privately; root/head trust and state proof interpretation remain application responsibilities.
  if not checked.ready: return PagedStreamResult[PagedContext](
      status: PagedStreamError.Uninitialized)
  var policy = checked.policy
  policy.work = contextBudget(policy.work, budget)
  var work = initWork(policy)
  let shape = checked.header.geometry
  let size = shape.contextBytes
  if size == 0:
    work.fail(PagedStreamError.UnsupportedPolicy) # V1 has no application context; never fabricate a successful empty head.
    return refused[PagedContext](work)
  let fixed = PagedStreamFixedBytes+41
  let available = uint64(policy.workingBytes)
  if available < fixed or size > (available-fixed) div 4 or size > uint64(high(int)):
    work.fail(PagedStreamError.LimitExceeded) # Four bounded context transports fit independently of proof/value allowances.
  if size > uint64(policy.work.readBytes) or uint64(policy.work.ioCalls) < 2 or uint64(
      policy.work.pageHashes) == 0:
    work.fail(PagedStreamError.LimitExceeded) # Obvious quota refusal precedes source dispatch and allocation.
  if work.status != PagedStreamError.None: return refused[PagedContext](work)
  if not io.checkExtent(checked.selected.byteLength, work): return refused[PagedContext](work)
  var payload = newSeq[byte](int(size))
  var cache = default(PageCache)
  if not io.authenticated(shape, checked.selected.pageRoot, uint64(shape.contextOffset), payload,
      cache, work):
    return refused[PagedContext](work) # No successfully copied prefix escapes a later IO/authentication refusal.
  if not io.checkExtent(checked.selected.byteLength, work): return refused[PagedContext](work)
  PagedStreamResult[PagedContext](status: PagedStreamError.None,
    completed: PagedContext(ready: true, selected: checked.selected, payload: payload,
        used: work.used))

func initialized*(inventory: PagedQueryInventory): bool =
  ## A valid empty inventory is distinct from the default owner.
  inventory.ready
func len*(inventory: PagedQueryInventory): int =
  ## Length observation grants no source or deletion authority.
  inventory.queries.len
func manifest*(inventory: PagedQueryInventory): PagedManifest {.requires: inventory.ready.} =
  ## Passive metadata binds every captured key to one exact admitted physical selection.
  inventory.selected
func counts*(inventory: PagedQueryInventory): PagedStreamCounts {.requires: inventory.ready.} =
  ## Complete success alone exposes cumulative inventory work counters.
  inventory.used
proc keys*(inventory: PagedQueryInventory): seq[StateKey] {.requires: inventory.ready.} =
  ## Copy fixed identities into detached caller transport without exposing private storage.
  result = newSeq[StateKey](inventory.queries.len)
  for index in 0..<result.len: result[index] = inventory.queries[index] # Each fixed key owns its bytes.
proc readPagedQueries*(io: PagedInput, checked: CheckedPagedArtifact,
    maximum: ElementLimit, budget: PagedWorkLimits): PagedStreamResult[PagedQueryInventory] =
  ## Authenticate every index row under one cumulative budget and return all keys or no prefix.
  if not checked.ready or io.read == nil or io.extent == nil:
    return PagedStreamResult[PagedQueryInventory](
        status: PagedStreamError.Uninitialized) # No callback or source authority is inferred.
  var policy = checked.policy
  policy.work = contextBudget(policy.work, budget)
  var work = initWork(policy)
  let shape = checked.header.geometry
  let count = shape.entries
  let fixed = PagedStreamFixedBytes+256
  let available = uint64(policy.workingBytes)
  if count > uint64(maximum): work.fail(PagedStreamError.LimitExceeded) # Caller query retention is independent of physical dataset ceilings.
  if count > uint64(high(int)) div uint64(sizeof(StateKey)):
    work.fail(PagedStreamError.LengthOverflow) # Prove host allocation before narrowing or multiplication.
  if count > (high(uint64)-4096) div 64:
    work.fail(PagedStreamError.LengthOverflow) # Every fixed descriptor endpoint remains representable.
  if available < fixed:
    work.fail(PagedStreamError.LimitExceeded) # Fixed workspace and transport metadata are reserved before dispatch.
  elif count > (available-fixed) div (4'u64*uint64(sizeof(StateKey))):
    work.fail(PagedStreamError.LimitExceeded) # Four possible key transports fit before allocating the first one.
  if uint64(policy.work.ioCalls) < 2 or uint64(policy.work.pageHashes) == 0:
    work.fail(PagedStreamError.LimitExceeded) # Even an empty inventory requires fresh authenticated source/EOF checks.
  if work.status != PagedStreamError.None: return refused[PagedQueryInventory](
      work) # Refusals dispatch no source callbacks or key prefix.
  let selected = checked.selected
  if not io.checkExtent(selected.byteLength, work): return refused[PagedQueryInventory](
      work) # Check actual extent before index access.
  var cache = default(PageCache)
  if not io.fetch(shape, selected.pageRoot, 0, cache, work): return refused[PagedQueryInventory](
      work) # Header authentication shares this operation's budget.
  let header = decodePagedHeader(cache.bytes, selected.chainId, selected.root, policy.dataset,
      policy.contextBytes)
  if header.error != PagedCodecError.None:
    work.fail(codecReason(header.error)) # Preserve structural or policy refusal without adopting keys.
    return refused[PagedQueryInventory](work)
  if header.value.bytes != checked.header.bytes:
    work.fail(PagedStreamError.ChangedInput) # A previously admitted header cannot be silently substituted.
    return refused[PagedQueryInventory](work)
  var queries = newSeq[StateKey](int(count))
  for ordinal in 0..<queries.len:
    # Every index page is authenticated against the captured tree; no budget/cache is reset between rows.
    var raw = default(array[PagedDescriptorBytes, byte])
    let offset = 4096+uint64(ordinal)*64
    if not io.authenticated(shape, selected.pageRoot, offset, raw, cache, work): return refused[
        PagedQueryInventory](work)
    let row = decodePagedDescriptor(raw, shape)
    if row.error != PagedCodecError.None:
      work.fail(codecReason(row.error)) # No malformed row can supply a successful query prefix.
      return refused[PagedQueryInventory](work)
    queries[ordinal] = row.value.key
  if not io.checkExtent(selected.byteLength, work): return refused[PagedQueryInventory](
      work) # Late shrink/growth still refuses the entire transport.
  PagedStreamResult[PagedQueryInventory](status: PagedStreamError.None,
    completed: PagedQueryInventory(ready: true, selected: selected, queries: queries,
        used: work.used))
