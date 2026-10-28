# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real light Services use independent current trust, asynchronous proof enrichment and selected paged restart without a complete state owner.
import std/assertions
import std/syncio
import std/envvars
import std/strutils
import std/base64
import std/monotimes
import std/times
import std/posix/posix
import ../../support/app_checkpoint_context
import ../../support/rpc_socket
import ../../support/storage_io
import ../../../src/app/services as app_services
import ../../../src/app/options as app_options
import ../../../src/app/chain as app_chain
import ../../../src/app/light_head as app_light_head
import ../../../src/app/light_runtime as app_light_runtime
import ../../../src/app/light_policy as app_light_policy
import ../../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../../src/app/checkpoint_trust as app_checkpoint_trust
import ../../../src/app/proof_query as app_proof_query
import ../../../src/app/proof_worker as app_proof_worker
import ../../../src/app/disk_worker as app_disk_worker
import ../../../src/app/light_store as app_light_store
import ../../../src/chain/provider as chain_provider
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/parameters as chain_parameters
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/header as codec_header
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/state/store as state_store
import ../../../src/state/proof_view as state_proof_view
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/state/planned_proof as state_planned_proof
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/rpc/protocol as rpc_protocol
import ../../../src/rpc/server as rpc_server
import ../../../src/storage/paged_store as storage_paged_store
import ../../../src/storage/paged_codec as storage_paged_codec
import ../../../src/storage/paged_stream as storage_paged_stream
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/crypto/primitives as crypto_primitives
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield only between bounded native scalar polls.
proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Each owned ignored fixture namespace survives without colliding with another invocation.
type Fixture = object ## Only fixed identities, detached proof bytes and independent authority paths survive fixture construction.
  hash: BlockHash
  root: StateRoot
  wire: seq[byte]
  trust, header, foreignTrust, foreignHeader: string
  policy: LightRuntimePolicy
proc putBytes(path: string, bytes: openArray[byte]) {.raises.} =
  ## Persist initialized independent fixture authority before runtime startup.
  var text = newString(bytes.len)
  for index in 0..<bytes.len: text[index] = char(bytes[
      index]) # Binary fixture files contain no implicit text conversion.
  writeFile(path, text)
proc fixture(): Fixture {.raises.} =
  ## The complete fixture map authors genuine selected witnesses and immediately retires every full-state alias.
  let owner = checkpointFixture()
  let source = owner.chainView.bestBlock.value
  let identity = captureApplicationCheckpointIdentity(owner).value
  let prefix = "light-runtime-" & $processId()
  result = Fixture(hash: source.blockHash, root: source.stateRoot, trust: prefix & ".trust",
    header: prefix & ".header", foreignTrust: prefix & ".foreign.trust", foreignHeader: prefix & ".foreign.header")
  let encoded = encodeApplicationCheckpointIdentity(identity, ByteLimit(4096)).value
  var sealed = newSeq[byte](source.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(source.header, sealed).error == HeaderError.None
  putBytes(result.trust, encoded)
  putBytes(result.header, sealed)
  let foreign = checkpointFixture(CheckpointFixtureVariant.State)
  putBytes(result.foreignTrust, encodeApplicationCheckpointIdentity(
      captureApplicationCheckpointIdentity(foreign).value, ByteLimit(4096)).value)
  putBytes(result.foreignHeader, sealed)
  var domain: seq[byte] = @[]
  for character in "RAGNAROK-CHAIN-V1\n": domain.add(byte(
      character)) # Independent network identity uses the documented configured-genesis domain.
  for octet in array[32, byte](source.blockHash): domain.add(octet)
  for octet in array[32, byte](source.stateRoot): domain.add(octet)
  for octet in source.chainParameters.encodeParameters: domain.add(octet)
  let profile = HeaderConfig(cores: source.cores, authorValidators: source.activeValidators,
    epochSlots: source.epochSlots, maxBytes: ByteLimit(262144))
  result.policy = lightRuntimePolicy(StorageChainId(array[32, byte](blake2b256(domain).value)),
      source.stateRoot, profile)
  var entries: seq[StateEntry] = @[]
  let snapshot = source.stateSnapshot
  for index in 0..<snapshot.commitment.entries:
    let key = snapshot.keyAt(StateEntryIndex(index)).value
    entries.add(StateEntry(key: key, value: snapshot.lookup(
        key).value.bytes)) # Complete-map generation is test-only evidence authoring.
  let proofs = generateStateProofs(entries, [chapterKey(StateChapter(11)), default(StateKey)],
    genesisStoreLimits().trie, result.policy.query.proof, result.policy.query.aggregate).value
  var queries = newSeq[StateProofQuery](proofs.len)
  for index in 0..<queries.len: queries[index] = proofs.queryAt(
      index).value # Genuine raw evidence is authenticated before transport encoding.
  let checked = verifyStateProofs(queries, source.stateRoot, result.policy.query.proof,
      result.policy.query.aggregate).value
  let view = captureProofView(checked, source.stateRoot, result.policy.query.view).value
  result.wire = encodeProofView(view, result.policy.query.view, result.policy.query.proof,
      result.policy.ingestion.wireBytes).value
proc configured(fixed: Fixture, directory: string, port: uint16, foreign = false): Options =
  ## Real CLI parsing selects memory or explicit paged disk independently of current checkpoint authority.
  var arguments = @["server", "--state-mode", "light", "--with-state", "--chain", getEnv(
      "RAGNAROK_APPLICATION_CHECKPOINT"),
    "--state-trust", if foreign: fixed.foreignTrust else: fixed.trust,
    "--state-header", if foreign: fixed.foreignHeader else: fixed.header]
  if directory.len > 0:
    for value in ["--state-storage", "disk", "--state-layout", "paged", "--state-db",
        directory]: arguments.add(value) # A distinct native directory never falls back to journal storage.
  if port != 0:
    arguments.add("--with-rpc"); arguments.add("--rpc-port"); arguments.add(
        $port) # The listener remains real and loopback-only.
  result = default(Options)
  assert parseCanonicalOptions(arguments, result)
proc idle(owner: Services): bool =
  ## Scalar exclusion observation never copies a partial graph during CPU/IO borrowing.
  not owner.stateProofActive and not owner.lightDiskActive
proc settle(owner: var Services) =
  ## Dispatcher collection ends each exact graph lease before any selected source can be inspected.
  let start = getMonoTime()
  while not owner.idle:
    assert owner.rpc.chainPaused and (getMonoTime()-start).inSeconds < 20
    assert owner.lightHead.error == LightRuntimeError.Busy
    owner.tick(0)
    discard pauseMicros(1000) # CPU and disk work share one serialized actor gate.
  assert not owner.rpc.chainPaused
proc claim(owner: var Services, peer: cint, call: string) =
  ## Transport parsing precedes staging, and the observed native lease remains held through Done.
  sendText(peer, call)
  let start = getMonoTime()
  while owner.idle:
    assert (getMonoTime()-start).inSeconds < 20
    owner.tick(0)
    discard pauseMicros(1000) # Socket delivery may follow the first dispatcher turn.
  assert owner.rpc.chainPaused
proc request(methodName: string, parameters = "[]"): string =
  ## Test calls use a stable JSON identity; connection-local native request IDs remain independently allocated.
  "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":" & quote(methodName) & ",\"params\":" & parameters & "}"
proc proofCall(fixed: Fixture): string =
  ## Exact current-header selection requests one present and one genuinely absent witness.
  request("ragnarok_requestStateProof", "[" & quote(base64.encode(array[32, byte](fixed.hash))) & ",[" &
    quote(base64.encode(array[31, byte](chapterKey(StateChapter(11))))) & "," & quote(base64.encode(
        default(array[31, byte]))) & "]]")
proc importCall(fixed: Fixture, corrupt = false): string =
  ## One same-length corrupt witness tests whole-batch authentication beyond framing admission.
  var wire = fixed.wire
  if corrupt: wire[wire.high] = wire[wire.high] xor 1 # No valid prefix may be adopted from a failed batch.
  request("ragnarok_importStateProof", "[" & quote(base64.encode(array[32, byte](fixed.hash))) &
      "," & quote(base64.encode(wire)) & "]")
proc roundtrip(owner: var Services, peer: cint, pending: var string, call: string): string =
  ## Acknowledgement reserves intent; only a later terminal message reports actual authenticated adoption/publication.
  owner.claim(peer, call)
  owner.settle()
  let acknowledgement = readPacket(owner.rpc, peer, pending)
  assert "\"id\":7" in acknowledgement and "\"error\"" notin acknowledgement
  readPacket(owner.rpc, peer, pending)
proc checkHead(owner: Services, count: int) =
  ## The full canonical provider remains unavailable in light mode; partial knowledge has its own guarded source.
  assert owner.lightMode and owner.chainView.bestBlock.error != GenesisError.None
  assert not owner.preparationActive and not owner.preparationAvailable
  let head = owner.lightHead.value
  assert head.proofView.len == count
  var unknown = default(array[31, byte])
  unknown[0] = 254
  assert head.proofView.lookup(StateKey(unknown)).error == ProofViewError.MissingWitness
proc metadata(owner: var Services, peer: cint, pending: var string, fixed: Fixture) =
  ## Detached RPC metadata exposes configured geometry and trusted root without complete-state/finality capabilities.
  for methodName in ["ragnarok_clientInfo", "ragnarok_lightHead", "bestBlock"]:
    sendText(peer, request(methodName))
    let reply = readPacket(owner.rpc, peer, pending)
    assert "\"error\"" notin reply and base64.encode(array[32, byte](fixed.hash)) in
        reply # Current metadata never fabricates a provider snapshot.
    if methodName == "ragnarok_clientInfo":
      assert "\"nodeMode\":\"light\"" in reply and "\"subscriptions\":false" in reply
      assert "ragnarok_importStateProof" in reply and "finalizedBlock" notin
          reply # Capability advertisement follows actual light contracts.
  sendText(peer, request("stateRoot", "[" & quote(base64.encode(array[32, byte](fixed.hash))) & "]"))
  assert base64.encode(array[32, byte](fixed.root)) in readPacket(owner.rpc, peer, pending)
  sendText(peer, request("finalizedBlock"))
  assert "\"error\"" in readPacket(owner.rpc, peer, pending)
proc knownSdkQuery(owner: var Services, fixed: Fixture) {.raises.} =
  ## An explicit SDK lease excludes automatic retirement throughout this IO observation, independently of scheduler delays.
  let plan = captureStateProofPlan([chapterKey(StateChapter(11)), default(StateKey)], ElementLimit(2)).value
  resetIo()
  let ticket = owner.beginStateProof(fixed.hash, plan, fixed.policy.query).value
  let start = getMonoTime()
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert (getMonoTime()-start).inSeconds < 20
    owner.tick(0)
    discard pauseMicros(1000) # Done SDK work retains its gate until explicit exact-ticket collection.
  assert owner.lightHead.error == LightRuntimeError.Busy and owner.rpc.chainPaused
  let completed = owner.collectStateProof(ticket)
  assert completed.kind == ProofWorkerCompletionKind.Completed and completed.value.error ==
      ProofQueryError.None
  let response = completed.value.value
  assert array[32, byte](response.blockHash) == array[32, byte](fixed.hash)
  let wire = response.bytes(fixed.policy.query.wireBytes).value
  let verified = decodePlannedProofs(wire, plan, fixed.root, fixed.policy.query.view,
    fixed.policy.query.proof, fixed.policy.query.aggregate, fixed.policy.query.wireBytes).value
  assert verified.lookup(chapterKey(StateChapter(11))).value.present
  assert not verified.lookup(default(StateKey)).value.present
  for operation in [readIo, writeIo, syncIo, lockIo, closeIo, renameIo, unlinkIo]:
    assert ioCalls(operation) == 0 # Cached query work performs no physical IO; no unrelated retirement turn was admitted.
proc scenario(fixed: Fixture, disk: bool) {.raises.} =
  ## Memory/paged modes share asynchronous CPU semantics; only disk adopts after a genuine native publication.
  let directory = if disk: "light-runtime-db-" & $processId() else: ""
  var owner = default(Services)
  var reader = default(PagedReader)
  defer:
    owner.close() # Every worker joins before independent fixture pins or socket owners retire.
    if reader.opened: discard reader.close
    resetIo()
  let reserved = reservation()
  discard posix.close(reserved.fd)
  let options = configured(fixed, directory, reserved.port)
  assert owner.start(options, "light runtime test")
  checkHead(owner, 0)
  let peer = client(reserved.port)
  defer: discard posix.close(peer)
  var pending = ""
  owner.rpc.upgrade(peer, pending)
  metadata(owner, peer, pending, fixed)
  let missing = owner.roundtrip(peer, pending, fixed.proofCall)
  assert "\"error\"" in missing and "\"proof\"" notin missing
  let invalid = owner.roundtrip(peer, pending, fixed.importCall(true))
  assert "\"error\"" in invalid
  checkHead(owner, 0)
  if disk: assert openPagedReader(reader, directory, fixed.policy.store.native).error ==
      PagedNativeError.None # An independent physical old pin enforces bounded retirement backpressure.
  let imported = owner.roundtrip(peer, pending, fixed.importCall)
  assert "ragnarok_stateProofImported" in imported and "\"knownFacts\":2" in imported and
      "\"error\"" notin imported
  checkHead(owner, 2)
  if disk:
    # The publication is adopted before separate cleanup; a held old reader yields Busy without withdrawing the new head.
    assert owner.lightDiskCompletion.kind == DiskCompletionKind.LightRetired
    assert owner.lightDiskCompletion.lightRetirementValue.nativeFailure.fileError == FileError.Busy
  knownSdkQuery(owner, fixed) # Its entire response/verification activation retires before another worker can borrow the source.
  let known = owner.roundtrip(peer, pending, fixed.proofCall)
  assert "\"proof\"" in known and "\"error\"" notin known
  if disk:
    # Pending cleanup prevents another mutation but permits reads between one-second retry attempts.
    assert reader.close == FileError.None
    let start = getMonoTime()
    while owner.lightDiskCompletion.kind != DiskCompletionKind.LightRetired or
        owner.lightDiskCompletion.lightRetirementValue.error != LightStoreError.None:
      assert (getMonoTime()-start).inSeconds < 5
      owner.tick(0)
      if not owner.idle: owner.settle() # Collection precedes outcome access.
      discard pauseMicros(1000)
  resetIo()
  let duplicate = owner.roundtrip(peer, pending, fixed.importCall)
  assert "\"knownFacts\":2" in duplicate and "\"error\"" notin duplicate
  assert ioCalls(writeIo) == 0 and ioCalls(renameIo) == 0 # A verified no-op creates no physical generation.
  owner.claim(peer, fixed.proofCall)
  owner.stopStateProofs()
  assert owner.idle and not owner.rpc.chainPaused
  discard readPacket(owner.rpc, peer, pending) # Intent acknowledgement is separate from joined stop outcome.
  assert "stopped" in readPacket(owner.rpc, peer, pending)
  assert "\"proof\"" in owner.roundtrip(peer, pending,
      fixed.proofCall) # Explicit CPU stop permits subsequent bounded reuse/restart.
  owner.claim(peer, fixed.proofCall)
  owner.close() # Joined close wins queued/running/Done CPU races without detached callbacks.
  assert owner.idle and not owner.rpc.chainPaused
  if disk:
    # Independently trusted reopen restores only authenticated stored knowledge, never complete-map ownership.
    assert owner.start(configured(fixed, directory, 0), "light disk restart")
    owner.tick(0)
    owner.settle()
    checkHead(owner, 2)
    owner.close()
    assert not owner.start(configured(fixed, directory, 0, true), "wrong independent root")
    owner.close()
    assert owner.start(configured(fixed, directory, 0), "preserved after refusal")
    checkHead(owner, 2)
    owner.close()
  else:
    assert owner.start(configured(fixed, "", 0), "light memory restart")
    checkHead(owner, 0) # Memory selection intentionally retains no disk evidence across lifetimes.
    owner.close()
proc waitDiskDone(owner: var Services) =
  ## Native Done retains every graph/RPC lease until an explicit collection or joined stop.
  let start = getMonoTime()
  while owner.lightDiskPhase != DiskWorkerPhase.Done:
    assert (getMonoTime()-start).inSeconds < 20
    discard pauseMicros(1000) # No dispatcher source access occurs during the native borrow.
  assert owner.lightDiskActive and owner.rpc.chainPaused
proc joinedDisk(fixed: Fixture, mode: int) {.raises.} =
  ## Deterministic Done/join controls preserve actual publication, cleanup and failed-IO receipts across close.
  let directory = "light-runtime-joined-" & $processId() & "-" & $mode
  var owner = default(Services)
  defer:
    owner.close() # Entered disk work always joins before observer flags or any graph alias retires.
    resetIo()
  let reserved = reservation()
  discard posix.close(reserved.fd)
  assert owner.start(configured(fixed, directory, reserved.port), "joined light disk")
  let peer = client(reserved.port)
  defer: discard posix.close(peer)
  var pending = ""
  owner.rpc.upgrade(peer, pending)
  owner.claim(peer, fixed.importCall)
  if mode == 2: armIo(writeIo, 0, 1, failedIo) # CPU ingestion has no storage writes; the next publication must consume this real fault.
  let start = getMonoTime()
  while not owner.lightDiskActive:
    assert (getMonoTime()-start).inSeconds < 20
    owner.tick(0)
    discard pauseMicros(1000) # Whole import collection/staging retires before native submission.
  owner.waitDiskDone()
  owner.stopStateProofs() # Another worker's idle shutdown cannot release the IO lease or its source aliases.
  owner.stopPreparation()
  assert owner.lightDiskActive and owner.rpc.chainPaused
  if mode == 1:
    owner.tick(0) # Adopt actual publication, then admit the independently staged predecessor cleanup.
    assert owner.lightDiskActive
    owner.waitDiskDone()
  owner.stopDiskPublication()
  assert owner.idle and not owner.rpc.chainPaused and owner.lightStorageFaulted
  let receipt = owner.lightDiskCompletion
  if mode == 1:
    assert receipt.kind == DiskCompletionKind.LightRetired and receipt.lightRetirementValue.error ==
        LightStoreError.None
    checkHead(owner, 2)
  elif mode == 2:
    assert pendingIo() == 0 and receipt.kind == DiskCompletionKind.LightCompleted
    assert receipt.lightValue.error != LightStoreError.None
    checkHead(owner, 0) # Failed entered IO never becomes an invented adopted prefix.
  else:
    assert receipt.kind == DiskCompletionKind.LightCompleted and receipt.lightValue.error ==
        LightStoreError.None
    checkHead(owner, 2) # Joined publication adoption precedes the successful terminal acknowledgement.
  discard readPacket(owner.rpc, peer, pending)
  let terminal = readPacket(owner.rpc, peer, pending)
  assert "ragnarok_stateProofImported" in terminal
  if mode == 2: assert "\"error\"" in terminal # Native failure remains a terminal refusal without successful proof coverage.
  else: assert "\"knownFacts\":2" in terminal # Publication/cleanup receipt kinds remain separate from query wire.
  owner.close()
  assert owner.lightDiskCompletion.kind == receipt.kind # Repeated joined close retains the actual last entered operation.
proc sdkLease(fixed: Fixture) {.raises.} =
  ## SDK queries preserve Busy through cancellation/Done, reject foreign collection and never start complete-state preparation.
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(configured(fixed, "", 0), "SDK light query lease")
  let plan = captureStateProofPlan([chapterKey(StateChapter(11))], ElementLimit(1)).value
  let admitted = owner.beginStateProof(fixed.hash, plan, fixed.policy.query).value
  assert owner.stateProofActive and owner.rpc.chainPaused
  assert owner.cancelStateProof(admitted)
  owner.stopPreparation()
  owner.stopDiskPublication() # An unrelated unstarted IO slot never releases this CPU lease.
  assert owner.stateProofActive and owner.rpc.chainPaused
  assert owner.collectStateProof(default(ProofWorkerTicket)).kind ==
      ProofWorkerCompletionKind.Uninitialized
  let start = getMonoTime()
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert (getMonoTime()-start).inSeconds < 20
    owner.tick(0)
    discard pauseMicros(1000) # SDK tickets retain explicit collection authority despite autonomous dispatcher turns.
  assert owner.lightHead.error == LightRuntimeError.Busy and owner.rpc.chainPaused
  assert owner.collectStateProof(admitted).kind == ProofWorkerCompletionKind.Cancelled
  assert owner.idle and not owner.rpc.chainPaused
  let next = owner.beginStateProof(fixed.hash, plan, fixed.policy.query).value
  owner.close() # Joined close wins the queued/running/Done race before its partial source is dropped.
  assert owner.collectStateProof(next).kind == ProofWorkerCompletionKind.Uninitialized
proc main() {.raises.} =
  ## Both selected backends use real Services and sockets; the configured full fixture retires before native borrowers start.
  let fixed = fixture()
  scenario(fixed, false)
  scenario(fixed, true)
  sdkLease(fixed)
  for mode in 0..<3: joinedDisk(fixed, mode) # Each distinct actual IO outcome has its own fresh physical namespace.
  echo "light runtime: ok"
try:
  main()
except:
  quit(2) # File, fixture, startup or native execution failures fail this suite.
