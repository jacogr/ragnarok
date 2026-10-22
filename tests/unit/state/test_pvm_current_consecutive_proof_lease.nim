# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native selected proofs retain the actual first adopted state across rearm refusal, collection and joined dispatcher shutdown.
import std/[assertions, envvars, syncio, monotimes, times]
import std/posix/posix
import ../../../src/app/[services, options, current_handoff, download_schedule, preparation_worker]
import ../../../src/quic/[current_block_download_loop, current_block_download_peers, current_block_download_stream]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/report_owned
import ../../../src/state/[store, proof_plan]
import ../../../src/codec/[bounded, state_trie]
import ../../../src/app/[proof_query, proof_worker]
import ../../support/proof_query_context
import ../../../src/storage/managed_manifest
import ../../../src/rpc/server
import ../../support/[current_application_context, current_services_disk_samples,
  block_download_transport, current_consecutive_context, current_rotated_sequence_context,
  current_consecutive_download_context,
  current_download_command_context, managed_storage_samples]
proc key(second: bool): CurrentDownloadPeerKey {.raises.} =
  ## Authenticated host identities come from the two independent local fixture certificates.
  let raw = readFile(getEnv(if second: "RAGNAROK_TEST_PEER_B" else: "RAGNAROK_TEST_PEER_A"))
  assert raw.len == 32
  var bytes = default(array[32, byte])
  for index in 0..<32: bytes[index] = byte(raw[index])
  CurrentDownloadPeerKey(bytes)
proc advance(dispatcher: var CurrentDownloadLoop, servers: var DownloadResponders,
    target: CurrentDownloadLoopStage, now = 0'u64) =
  ## Bounded native polling preserves the authored monotonic deadline until this exact stage is observed.
  let started = getMonoTime()
  while dispatcher.stage != target:
    assert (getMonoTime()-started).inSeconds < 20, "bounded current dispatcher stage " & $target
    assert servers.poll()
    assert dispatcher.tick(CurrentDownloadLoopTick(now)) == CurrentDownloadLoopError.None
    yieldCurrentDiskThread() # Independent scheduler yield touches no leased canonical/input aliases.
proc transfer(fixture: CurrentConsecutiveFixture, join, disk, managed: bool) {.raises.} =
  ## The first real adoption supplies the selected proof owner before another child can be rearmed.
  var path = "pvm-current-consecutive-proof-lease-chain"
  var database = "pvm-current-consecutive-proof-lease-state-" & $getMonoTime().ticks
  let context = fixture.seed
  writeFile(path, context.currentApplicationText)
  defer:
    discard posix.unlink(path.toCString())
    if disk:
      if managed: removeManagedSample(database, [ManagedEpoch(1)])
      else: discard posix.unlink(database.toCString()) # Join all owners before retiring exact test-owned storage.
  var owner = default(Services)
  var dispatcher = default(CurrentDownloadLoop)
  var servers = default(DownloadResponders)
  defer:
    dispatcher.close()
    servers.close()
    owner.close() # Dispatcher ends its exclusive Services borrow before canonical shutdown.
  let port = 0'u16
  var options = default(Options)
  if disk:
    options = currentDiskOptions(path, database, managed, port)
  else:
    assert parseOptions(@["server", "--with-state", "--chain", path], options)
  assert owner.start(options, "current dispatcher")
  let original = owner.stateSnapshot.value
  var requests: seq[array[42, byte]] = @[]
  var responses: seq[seq[byte]] = @[]
  for index in 0..1:
    requests.add(currentExpectedRequest(array[32, byte](fixture.heads[index].blockHash)))
    responses.add(currentConsecutiveResponse(fixture.children[index]))
  assert servers.openSequenceResponders(requests, responses, @[Healthy, Healthy])
  var policy = currentConsecutivePolicy()
  policy.attemptTimeout = CurrentDownloadAttemptTimeout(100)
  assert dispatcher.configure(owner, @[DownloadPeerId(2)], [], policy, CurrentDownloadLoopTick(
      0)) == CurrentDownloadLoopError.None
  assert dispatcher.openPeer(DownloadPeerId(2), key(true), servers.port(true), getEnv(
      "RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000") ==
      CurrentDownloadPeerError.None
  dispatcher.advance(servers, CurrentDownloadLoopStage.Adopted)
  assert dispatcher.completed
  equalCurrentDiskMap(owner.stateSnapshot.value, fixture.heads[1].stateSnapshot)
  let parent = owner.stateSnapshot.value
  assert not sameStateSnapshot(original, parent)
  let selected = owner.chainView.bestBlock.value.blockHash
  let key = parent.keyAt(StateEntryIndex(0)).value
  let plan = captureStateProofPlan([key], ElementLimit(1)).value
  var proofPolicy = queryLimits()
  proofPolicy.map.items = ElementLimit(65536)
  proofPolicy.map.nodes = TrieNodeLimit(131071)
  proofPolicy.map.perValue = ByteLimit(1048576)
  proofPolicy.map.totalValueBytes = ByteLimit(8388608)
  let admitted = owner.beginStateProof(selected, plan, proofPolicy)
  assert admitted.error == StateProofAdmissionError.None
  assert dispatcher.nextChild([], CurrentDownloadLoopTick(1)) ==
      CurrentDownloadLoopError.ServicesBusy
  let started = getMonoTime()
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    yieldCurrentDiskThread() # Done remains exclusively borrowed until actual collection or joined close.
  assert owner.stateProofActive and owner.rpc.chainPaused
  assert dispatcher.nextChild([], CurrentDownloadLoopTick(1)) ==
      CurrentDownloadLoopError.ServicesBusy
  if join:
    dispatcher.close() # Join the actual proof before dispatcher-owned graph aliases can retire.
    assert owner.collectStateProof(admitted.value).kind == ProofWorkerCompletionKind.Uninitialized
  else:
    let completion = owner.collectStateProof(admitted.value)
    assert completion.kind == ProofWorkerCompletionKind.Completed
    assert completion.value.error == ProofQueryError.None
    let response = completion.value.value
    assert array[32, byte](response.blockHash) == array[32, byte](selected)
    assert array[32, byte](response.stateRoot) == array[32, byte](parent.commitment.root)
    assert dispatcher.nextChild([], CurrentDownloadLoopTick(1)) == CurrentDownloadLoopError.None
    dispatcher.advance(servers, CurrentDownloadLoopStage.Adopted, 1)
    assert dispatcher.completed
    equalCurrentDiskMap(owner.stateSnapshot.value, fixture.heads[2].stateSnapshot)
  let adopted = if join: 1 else: 2
  dispatcher.close()
  assert not owner.stateProofActive and not owner.rpc.chainPaused
  equalCurrentDiskMap(owner.stateSnapshot.value, fixture.heads[adopted].stateSnapshot)
  assert servers.requestCount(true) == adopted and servers.requestCount(false) == 0
  assert owner.chainView.retainedCount == adopted+1
  servers.close()
  owner.close()
  if disk:
    assert owner.start(options, "strict prefix restart after selected proof")
    equalCurrentDiskMap(owner.stateSnapshot.value, fixture.heads[adopted].stateSnapshot)
    assert owner.chainView.retainedCount == adopted+1
    owner.close()

proc main() {.raises.} =
  ## Actual first-child state supplies proof authority; collection resumes the next child and joined shutdown preserves the prefix.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  # Exercise the same real transport/lifecycle assertions before and after the signed slot12 rotation.
  for fixture in [currentConsecutiveFixture(decodeOwnedReport(bytes, 2).value, 2),
      currentRotatedSequenceFixture(decodeOwnedReport(bytes, 2).value, 2)]:
    for join in [false, true]:
      transfer(fixture, join, false, false)
      transfer(fixture, join, true, false)
      transfer(fixture, join, true, true)
try:
  main()
except:
  quit(2) # A scalar Done observation cannot authorize graph retirement or a second adoption.
echo "PVM current consecutive proof lease passed"
