# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted partial query projection and bounded proof ingestion preserve exact identities, unknown facts and whole-request authentication.
# @@Verification={"arc":"light_proof_requests_arc_release"}
import std/assertions
import std/syncio
import std/monotimes
import std/times
import ../../support/testing_arc_evidence
import ../../support/storage_disk_history_context
import ../../support/app_checkpoint_context
import ../../../src/app/proof_query as app_proof_query
import ../../../src/app/proof_worker as app_proof_worker
import ../../../src/app/light_proof_import as app_light_proof_import
import ../../../src/app/light_head as app_light_head
import ../../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../../src/app/checkpoint_trust as app_checkpoint_trust
import ../../../src/app/chain as app_chain
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/header as codec_header
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/crypto/primitives as crypto_primitives
import ../../../src/state/store as state_store
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/state/proof_view as state_proof_view
import ../../../src/state/proof_service as state_proof_service
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/state/planned_proof as state_planned_proof
proc headerWire(sourceBlock: BlockSnapshotResult): seq[byte] =
  ## Test-only complete snapshots supply independently chosen canonical header bytes, never partial-root inference.
  let selected = sourceBlock.value.header
  result = newSeq[byte](selected.headerInfo.value.consumed)
  assert encodeOwnedHeader(selected, result).error == HeaderError.None
proc trust(sourceBlock: BlockSnapshotResult): TrustedApplicationCheckpoint =
  ## Caller-selected identity/header inputs are captured before the light owner sees proof evidence.
  let owner = initApplicationChain(genesisView(sourceBlock)).value
  let identity = captureApplicationCheckpointIdentity(owner).value
  let encoded = encodeApplicationCheckpointIdentity(identity, ByteLimit(4096)).value
  let captured = captureCheckpointTrust(encoded, sourceBlock.headerWire, ByteLimit(1048576))
  assert captured.error == CheckpointTrustError.None
  captured.value
proc policy(sourceBlock: BlockSnapshotResult): LightHeadLimits =
  ## Active validator geometry is selected independently from complete genesis context, never inferred from fetch parameters or partial facts.
  LightHeadLimits(header: HeaderConfig(cores: sourceBlock.value.cores,
    authorValidators: sourceBlock.value.activeValidators, epochSlots: sourceBlock.value.epochSlots,
    maxBytes: ByteLimit(262144)), headers: ElementLimit(3), headerBytes: ByteLimit(1048576),
    view: ProofViewLimits(items: ElementLimit(16), valueBytes: ByteLimit(4194304)))
proc entries(snapshot: StateStoreSnapshot): seq[StateEntry] =
  ## An independent complete fixture map is used only to author genuine membership/absence proofs.
  result = @[]
  for index in 0..<snapshot.commitment.entries:
    let key = snapshot.keyAt(StateEntryIndex(index)).value
    result.add(StateEntry(key: key, value: snapshot.lookup(key).value.bytes))
proc batch(snapshot: StateStoreSnapshot, keys: openArray[StateKey],
    limits: StateStoreLimits): VerifiedStateProofBatch =
  ## Full fixture generation and exact-root verification precede every partial view used by the application API.
  let perProof = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(4194304))
  let aggregate = StateProofBatchLimits(items: ElementLimit(16), nodes: ElementLimit(4096),
      valueBytes: ByteLimit(4194304))
  let generated = generateStateProofs(snapshot.entries, keys, limits.trie, perProof, aggregate)
  assert generated.error == StateProofError.None
  var queries = newSeq[StateProofQuery](generated.value.len)
  for index in 0..<queries.len: queries[index] = generated.value.queryAt(
      index).value # Immutable raw witnesses carry no trust until verified.
  let checked = verifyStateProofs(queries, snapshot.commitment.root, perProof, aggregate)
  assert checked.error == StateProofError.None
  checked.value
func key(value: byte): StateKey =
  ## High-byte fixture keys distinguish genuine absent witnesses from unrequested unknown facts.
  var bytes = default(array[31, byte])
  for index in 0..<bytes.len: bytes[index] = value
  StateKey(bytes)
proc checksum(bytes: var seq[byte]) =
  ## Independent identity-frame oracle rehashes the documented fixed 206-byte payload after one deliberate scalar change.
  assert bytes.len == 238
  let hashed = blake2b256(bytes.toOpenArray(0, 205))
  assert hashed.error == CryptoError.None
  let digest = array[32, byte](hashed.value)
  for index in 0..<32: bytes[206+index] = digest[index]
proc rootTrust(original: TrustedApplicationCheckpoint,
    root: StateRoot): TrustedApplicationCheckpoint =
  ## Test-only operator posterior-root choice remains independent of the sealed header's prior root; no consensus certificate is claimed.
  var identity = encodeApplicationCheckpointIdentity(original.identity, ByteLimit(4096)).value
  let digest = array[32, byte](root)
  for index in 0..<32: identity[48+index] = digest[index]
  checksum(identity)
  var header = newSeq[byte](original.sealedHeaderLength)
  assert original.copySealedHeader(header)
  let captured = captureCheckpointTrust(identity, header, ByteLimit(1048576))
  assert captured.error == CheckpointTrustError.None
  captured.value
proc queryPolicy(): ProofQueryLimits =
  ## Zero complete-map/hash allowances prove a partial request never enters complete-state generation.
  ProofQueryLimits(proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(
      4194304)),
    aggregate: StateProofBatchLimits(items: ElementLimit(16), nodes: ElementLimit(4096),
        valueBytes: ByteLimit(4194304)),
    view: ProofViewLimits(items: ElementLimit(16), valueBytes: ByteLimit(4194304)),
    wireBytes: ByteLimit(1048576), hashes: ProofHashLimit(0))
proc importPolicy(): LightProofImportLimits =
  ## Two independent verification passes fit a finite primitive-call cap, separate from wire/node/value retention.
  let selected = queryPolicy()
  LightProofImportLimits(proof: selected.proof, aggregate: selected.aggregate, view: selected.view,
    wireBytes: selected.wireBytes, hashes: ElementLimit(8192))
proc known(fixture: DiskHistoryFixture): LightApplicationHead =
  ## The complete fixture only authors genuine evidence; production owners retain two selected partial facts.
  let source = fixture.blocks[0]
  let checked = batch(source.value.stateSnapshot, [chapterKey(StateChapter(11)), key(255)],
      fixture.policy)
  let view = captureProofView(checked, source.trust.identity.stateRoot, source.policy.view).value
  captureLightHead(source.trust, view, source.policy).value
proc plan(): StateProofPlan =
  ## Canonical generic planning sorts independent present/absent requests without inspecting values or hashing.
  captureStateProofPlan([key(255), chapterKey(StateChapter(11))], ElementLimit(16)).value
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count actual primitive invocations independently of request estimates.
proc resetHashes(flags: cint) {.importc: "ro_fail", cdecl.}
  ## The existing test observer resets counts before a bounded workload and can refuse hashing.
proc projection(fixture: DiskHistoryFixture) =
  ## Root/block selection stays independent of response bytes, while unknown evidence is refused atomically.
  let head = fixture.known
  let selected = queryPolicy()
  resetHashes(0)
  let request = captureProofQuery(head, plan(), selected).value
  assert request.valid and uint64(request.estimatedHashes) == 0 and hashCalls() == 0
  let response = executeProofQuery(request).value
  assert hashCalls() == 0
  assert array[32, byte](response.blockHash) == array[32, byte](
      head.current.value.identity.blockHash)
  assert array[32, byte](response.stateRoot) == array[32, byte](head.stateRoot)
  let wire = response.bytes(selected.wireBytes).value
  let verified = decodePlannedProofs(wire, plan(), head.stateRoot, selected.view, selected.proof,
      selected.aggregate, selected.wireBytes).value
  assert verified.lookup(chapterKey(StateChapter(11))).value.present
  assert not verified.lookup(key(255)).value.present
  assert verified.lookup(key(254)).error == ProofViewError.MissingWitness
  let unknown = captureStateProofPlan([key(254)], ElementLimit(1)).value
  let missing = executeProofQuery(captureProofQuery(head, unknown, selected).value)
  assert missing.error == ProofQueryError.ViewFailure and missing.viewError ==
      ProofViewError.MissingWitness
  let service = planProofAccount(ServiceIndex(42), ElementLimit(1)).value
  let missingService = executeProofQuery(captureProofQuery(head, service, selected).value)
  assert missingService.error == ProofQueryError.ServiceFailure and missingService.serviceError ==
      ServiceProofError.MissingWitness
  assert captureProofQuery(default(LightApplicationHead), plan(), selected).error ==
      ProofQueryError.InvalidSelection
  assert captureProofQuery(head, default(StateProofPlan), selected).error ==
      ProofQueryError.InvalidPlan
  for channel in 0..<3:
    # Query count, retained view and minimum wire bounds refuse before any projected proof allocation.
    var short = selected
    case channel
    of 0: short.aggregate.items = ElementLimit(1)
    of 1: short.view.items = ElementLimit(1)
    else: short.wireBytes = ByteLimit(7) # Every canonical envelope requires its fixed header.
    assert captureProofQuery(head, plan(), short).error == ProofQueryError.LimitExceeded
  var nodes = 0'u64
  for index in 0..<head.proofView.len: nodes += uint64(head.proofView.lookupAt(
      index).value.witness.len) # Independently captured fixture witnesses determine the exact aggregate.
  var exact = selected
  exact.aggregate.nodes = ElementLimit(nodes)
  exact.wireBytes = ByteLimit(uint64(wire.len))
  assert executeProofQuery(captureProofQuery(head, plan(), exact).value).error ==
      ProofQueryError.None
  exact.aggregate.nodes = ElementLimit(nodes-1)
  assert executeProofQuery(captureProofQuery(head, plan(), exact).value).proofError ==
      StateProofError.LimitExceeded
  exact = selected
  exact.wireBytes = ByteLimit(uint64(wire.len-1))
  assert executeProofQuery(captureProofQuery(head, plan(), exact).value).error !=
      ProofQueryError.None
proc importedWire(head: LightApplicationHead): seq[byte] =
  ## The same canonical existing proof transport is independent of importer implementation.
  executeProofQuery(captureProofQuery(head, plan(), queryPolicy()).value).value.bytes(queryPolicy().wireBytes).value
proc ingestion(fixture: DiskHistoryFixture) =
  ## Host capture copies stable bytes without crypto; worker execution verifies the exact whole batch and checkpoint identity.
  let head = fixture.known
  let selected = importPolicy()
  var wire = importedWire(head)
  resetHashes(0)
  let request = captureLightProofImport(head, wire, selected).value
  assert request.valid and hashCalls() == 0
  let expected = uint64(request.estimatedHashes)
  wire[8] = wire[8] xor 1 # Caller mutation must not alter the privately captured request.
  let imported = executeLightProofImport(request).value
  assert hashCalls() > 0 and uint64(hashCalls()) <= expected
  assert imported.valid and imported.batch.valid and imported.batch.len == 2
  assert sameApplicationCheckpoint(imported.identity, head.current.value.identity)
  let empty = captureLightHead(fixture.blocks[0].trust, fixture.blocks[0].policy).value
  assert mergeLightProofs(empty, imported.batch, fixture.blocks[0].policy).value.proofView.len == 2
  let successor = rootTrust(fixture.blocks[1].trust, head.stateRoot)
  let newer = advanceLightHead(head, successor, head.proofView, fixture.blocks[0].policy).value
  assert not sameApplicationCheckpoint(imported.identity,
      newer.current.value.identity) # Equal roots cannot hide an old import selector.
  assert executeLightProofImport(default(LightProofImport)).error == LightImportError.Uninitialized
  assert captureLightProofImport(default(LightApplicationHead), importedWire(head),
      selected).error == LightImportError.InvalidSelection
  let original = importedWire(head)
  var exact = selected
  exact.hashes = ElementLimit(expected)
  assert captureLightProofImport(head, original, exact).error == LightImportError.None
  for channel in 0..<4:
    # Each independent admission channel refuses before any hash work.
    var short = selected
    case channel
    of 0: short.hashes = ElementLimit(expected-1)
    of 1: short.aggregate.items = ElementLimit(1)
    of 2: short.view.items = ElementLimit(1)
    else: short.wireBytes = ByteLimit(uint64(original.len-1)) # Wire copy policy is independent of decoded proof values.
    resetHashes(0)
    assert captureLightProofImport(head, original, short).error == LightImportError.LimitExceeded
    assert hashCalls() == 0
  var truncated = original
  truncated.setLen(7)
  assert captureLightProofImport(head, truncated, selected).error == LightImportError.InvalidFormat
  var corrupt = original
  corrupt[0] = 0
  assert captureLightProofImport(head, corrupt, selected).error == LightImportError.InvalidFormat
  var trailing = original
  trailing.add(0)
  assert executeLightProofImport(captureLightProofImport(head, trailing,
      selected).value).viewError == ProofViewError.NonCanonical
  let foreign = captureLightHead(fixture.blocks[1].trust, fixture.blocks[1].policy).value
  assert executeLightProofImport(captureLightProofImport(foreign, original,
      selected).value).error == LightImportError.ProofFailure
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Test-only scalar polling never owns or mutates a proof graph.
proc waitDone(worker: var StateProofWorker) =
  ## Only locked scalar state is observed while admitted request aliases remain frozen.
  let started = getMonoTime()
  while worker.phase != ProofWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 30 # Bound every native thread test wait by monotonic time.
    discard pauseMicros(1000) # Yield without touching canonical/request ARC aliases.
proc workers(fixture: DiskHistoryFixture) {.raises.} =
  ## One existing CPU slot reuses query/ingestion payloads without mixing completion types or losing cancellation retirement.
  let head = fixture.known
  let wire = importedWire(head)
  var query = captureProofQuery(head, plan(), queryPolicy()).value
  var request = captureLightProofImport(head, wire, importPolicy()).value
  var worker = default(StateProofWorker)
  var foreign = default(StateProofWorker)
  defer:
    worker.close() # Join before any fixed trusted metadata, wire, view or query alias can retire.
    foreign.close()
  assert worker.submit(request).error == ProofWorkerError.Closed and request.valid
  assert worker.start() and foreign.start()
  var empty = default(LightProofImport)
  assert worker.submit(empty).error == ProofWorkerError.NotReady
  let ticket = worker.submit(request).value
  assert not request.valid
  assert worker.submit(empty).error == ProofWorkerError.Busy
  assert not foreign.cancel(ticket)
  assert worker.collect(default(ProofWorkerTicket)).kind == ProofWorkerCompletionKind.Uninitialized
  waitDone(worker)
  assert worker.submit(empty).error == ProofWorkerError.Busy
  let imported = worker.collect(ticket)
  assert imported.kind == ProofWorkerCompletionKind.Imported
  assert imported.importedValue.error == LightImportError.None
  assert imported.importedValue.value.batch.len == 2
  assert sameApplicationCheckpoint(imported.importedValue.value.identity,
      head.current.value.identity)
  assert worker.collect(ticket).kind == ProofWorkerCompletionKind.Uninitialized
  let queryTicket = worker.submit(query).value
  assert not query.valid
  waitDone(worker)
  let response = worker.collect(queryTicket)
  assert response.kind == ProofWorkerCompletionKind.Completed and response.value.error ==
      ProofQueryError.None
  var fullPolicy = queryPolicy()
  fullPolicy.map = fixture.policy.trie
  fullPolicy.hashes = ProofHashLimit(10000000)
  query = captureProofQuery(fixture.blocks[0], plan(), fullPolicy).value
  let fullTicket = worker.submit(query).value
  waitDone(worker)
  assert worker.collect(fullTicket).value.error ==
      ProofQueryError.None # Complete-map generation remains a distinct working source in the same slot.
  var trailing = wire
  trailing.add(0)
  request = captureLightProofImport(head, trailing, importPolicy()).value
  let failed = worker.submit(request).value
  waitDone(worker)
  assert worker.collect(failed).importedValue.viewError ==
      ProofViewError.NonCanonical # Failed ingestion remains its own typed completion.
  for iteration in 0..<24:
    # Queued/running and already-Done cancellation retain capacity until exact collection, exposing no verified prefix.
    request = captureLightProofImport(head, wire, importPolicy()).value
    let cancelled = worker.submit(request).value
    if iteration mod 2 == 0: waitDone(worker) # Exercise cancellation after a genuine verified outcome exists too.
    assert worker.cancel(cancelled)
    waitDone(worker)
    assert worker.submit(empty).error == ProofWorkerError.Busy
    assert worker.collect(cancelled).kind == ProofWorkerCompletionKind.Cancelled
    assert worker.phase == ProofWorkerPhase.Idle
  worker.close()
  assert worker.start()
  request = captureLightProofImport(head, wire, importPolicy()).value
  let restarted = worker.submit(request).value
  assert not worker.cancel(ticket) # Old namespace authority cannot cancel a fresh ingestion.
  assert worker.cancel(restarted)
  worker.close() # Joined cancellation drops CPU-only evidence, never a native publication receipt.
  assert worker.collect(restarted).kind == ProofWorkerCompletionKind.Uninitialized
proc cycle(head: LightApplicationHead, request: LightProofImport) =
  ## Direct checked execution makes whole-activation ARC accounting meaningful without summing thread-local allocator counters.
  let response = executeProofQuery(captureProofQuery(head, plan(), queryPolicy()).value).value
  assert response.valid
  let imported = executeLightProofImport(request).value
  assert imported.batch.len == 2 and sameApplicationCheckpoint(imported.identity,
      head.current.value.identity)
proc main() {.raises.} =
  ## Independent complete fixtures author proofs; production requests retain only trusted fixed metadata and partial evidence.
  let fixture = diskHistoryFixture(1, false)
  projection(fixture)
  ingestion(fixture)
  workers(fixture)
  let head = fixture.known
  let request = captureLightProofImport(head, importedWire(head), importPolicy()).value
  cycle(head, request)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(head, request) # Private response buffers, decoded proof graphs and verified batch owners retire every cycle.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("app_light_proof_requests", 1000, before, after)
  echo "light proof requests PASS"
try:
  main()
except:
  quit(2) # Fixture, genuine cryptographic and thread failures cannot count as successful request ownership evidence.
