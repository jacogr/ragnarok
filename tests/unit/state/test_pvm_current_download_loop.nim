# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual current network downloads cross retry, managed execution, durable/RPC adoption, deadlines and proof exclusion in separate turns.
import std/assertions
import std/envvars
import std/syncio
import std/monotimes
import std/times
import std/base64
import std/strutils
import std/posix/posix
import ../../../src/app/services as app_services
import ../../../src/app/options as app_options
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/app/current_handoff as app_current_handoff
import ../../../src/app/candidate as app_candidate
import ../../../src/app/download_schedule as app_download_schedule
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/proof_query as app_proof_query
import ../../../src/app/proof_worker as app_proof_worker
import ../../../src/app/chain as app_chain
import ../../../src/quic/current_block_download_loop as quic_current_block_download_loop
import ../../../src/quic/current_block_download_peers as quic_current_block_download_peers
import ../../../src/quic/current_block_download_stream as quic_current_block_download_stream
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/state/store as state_store
import ../../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/rpc/server as rpc_server
import ../../support/state_current_application_context
import ../../support/state_current_services_disk_samples
import ../../support/state_accumulation_current_chain_context
import ../../support/state_accumulation_current_candidate_context
import ../../support/app_block_download_transport
import ../../support/app_proof_query_context
import ../../support/app_managed_storage_samples
import ../../support/rpc_socket
type LoopWitness {.pure.} = enum ## Explicit stages distinguish actual adoption from unwanted/lost execution or handoff.
  Adopt, CancelDone, Joined, LostHandoff
proc limits(retry = false): CurrentDownloadLoopLimits =
  ## Every current network and execution ceiling is explicitly selected, with no legacy completion policy.
  CurrentDownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(2),
    attempts: (if retry: 2'u64 else: 1'u64), retryDelay: DownloadRetryDelay(10)),
    input: CurrentBlockInputLimits(blockBytes: ByteLimit(100000), ancestorBytes: ByteLimit(10000),
      ancestors: ElementLimit(4), discoverAncestors: true), candidate: currentCandidateLimits(),
    stream: CurrentDownloadStreamLimits(readBytes: ByteLimit(73), writeBytes: ByteLimit(3),
      timeout: CurrentDownloadTimeout(50)), attemptTimeout: CurrentDownloadAttemptTimeout(100))
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
proc assertPreparationLease(owner: Services) =
  ## Observe the actual managed lease without teaching the compiler stale facts about pointer-owned dispatcher mutations.
  assert owner.preparationActive and owner.rpc.chainPaused
proc transfer(context: CurrentChainFixture, witness = LoopWitness.Adopt,
    disk = false, managed = false, network = false, retry = false) {.raises.} =
  ## Real TLS/current execution reaches the requested producer stage before any host acknowledgment can authorize progress.
  var path = "pvm-current-download-loop-chain"
  var database = "pvm-current-download-loop-state"
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
  var port = 0'u16
  if network:
    let reserved = reservation()
    port = reserved.port
    discard posix.close(reserved.fd)
  var options = default(Options)
  if disk:
    options = currentDiskOptions(path, database, managed, port)
  else:
    assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  assert owner.start(options, "current dispatcher")
  let parent = owner.stateSnapshot.value
  var request = default(array[42, byte])
  request[0] = 128
  request[1] = 37
  request[38] = 1
  for index, octet in array[32, byte](owner.chainView.bestBlock.value.blockHash): request[
      index+5] = octet
  let body = context.currentDiskChildBytes
  assert body.len <= high(int)-4 and uint64(body.len) <= 0xffffffff'u64
  var response = newSeq[byte](body.len+4)
  for index in 0..<4: response[index] = byte((uint64(body.len) shr (8*index)) and 255)
  for index, octet in body: response[index+4] = octet
  assert servers.openResponders(request, response, Healthy, emptyFirst = retry)
  let peers = if retry: @[DownloadPeerId(1), DownloadPeerId(2)] else: @[DownloadPeerId(2)]
  assert dispatcher.configure(owner, peers, [], limits(retry), CurrentDownloadLoopTick(0)) ==
      CurrentDownloadLoopError.None
  if retry:
    assert dispatcher.openPeer(DownloadPeerId(1), key(false), servers.port(false),
      getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000") ==
          CurrentDownloadPeerError.None
  assert dispatcher.openPeer(DownloadPeerId(2), key(true), servers.port(true),
    getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000") ==
        CurrentDownloadPeerError.None
  dispatcher.advance(servers, CurrentDownloadLoopStage.Preparing)
  assertPreparationLease(owner)
  assert not dispatcher.completed
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    assert servers.poll()
    yieldCurrentDiskThread() # Deliberately leave Done uncollected until the authored producer action.
  if witness == LoopWitness.CancelDone:
    assert dispatcher.tick(CurrentDownloadLoopTick(100)) == CurrentDownloadLoopError.None
    assert dispatcher.stage == CurrentDownloadLoopStage.Cancelling
    assertPreparationLease(owner)
    dispatcher.advance(servers, CurrentDownloadLoopStage.Exhausted, 100)
    assert not dispatcher.completed and sameStateSnapshot(parent, owner.stateSnapshot.value)
    assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  elif witness == LoopWitness.Joined:
    dispatcher.close()
    assert dispatcher.stage == CurrentDownloadLoopStage.Closed and not owner.preparationActive
    assert not owner.rpc.chainPaused and owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
    assert sameStateSnapshot(parent, owner.stateSnapshot.value)
  else:
    dispatcher.advance(servers, CurrentDownloadLoopStage.Queued)
    assert not dispatcher.completed and sameStateSnapshot(parent, owner.stateSnapshot.value)
    if witness == LoopWitness.LostHandoff:
      assert owner.cancelCurrentAccumulation()
      assert dispatcher.tick(CurrentDownloadLoopTick(0)) == CurrentDownloadLoopError.LostHandoff
      assert not dispatcher.completed and sameStateSnapshot(parent, owner.stateSnapshot.value)
    else:
      dispatcher.advance(servers, CurrentDownloadLoopStage.Adopted)
      assert dispatcher.completed and dispatcher.adoption.error == CurrentHandoffError.None
      assert array[32, byte](dispatcher.adoption.value.blockHash) == array[32, byte](
          owner.chainView.bestBlock.value.blockHash)
      equalCurrentDiskMap(owner.stateSnapshot.value, context.source.currentConsensusState.value)
      assert servers.requestCount(true) == 1
      if retry: assert servers.requestCount(false) == 1 # Empty first peer never implied terminal adoption.
      assert dispatcher.nextChild([], CurrentDownloadLoopTick(1)) == CurrentDownloadLoopError.None
      assert dispatcher.stage == CurrentDownloadLoopStage.Waiting and not dispatcher.completed
      dispatcher.close()
      if disk:
        owner.close()
        assert owner.start(options, "strict downloaded current restart")
        equalCurrentDiskMap(owner.stateSnapshot.value, context.source.currentConsensusState.value)
proc proofs(context: CurrentChainFixture) {.raises.} =
  ## Actual selected-state native borrowing blocks configuration and pauses an existing dispatcher until collection/join.
  var path = "pvm-current-download-loop-proof-chain"
  writeFile(path, context.currentApplicationText)
  defer: discard posix.unlink(path.toCString())
  var owner = default(Services)
  var dispatcher = default(CurrentDownloadLoop)
  defer:
    dispatcher.close()
    owner.close()
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  assert owner.start(options, "current dispatcher proof exclusion")
  let parent = owner.stateSnapshot.value
  let selected = owner.chainView.bestBlock.value.blockHash
  let key = parent.keyAt(StateEntryIndex(0)).value
  let plan = captureStateProofPlan([key], ElementLimit(1)).value
  var policy = queryLimits()
  policy.map.items = ElementLimit(65536)
  policy.map.nodes = TrieNodeLimit(131071)
  policy.map.perValue = ByteLimit(1048576)
  policy.map.totalValueBytes = ByteLimit(8388608)
  let admitted = owner.beginStateProof(selected, plan, policy)
  assert admitted.error == StateProofAdmissionError.None
  assert dispatcher.configure(owner, [DownloadPeerId(2)], [], limits(), CurrentDownloadLoopTick(
      0)) == CurrentDownloadLoopError.ServicesBusy
  let started = getMonoTime()
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    yieldCurrentDiskThread()
  let completion = owner.collectStateProof(admitted.value)
  assert completion.kind == ProofWorkerCompletionKind.Completed
  assert completion.value.error == ProofQueryError.None
  assert dispatcher.configure(owner, [DownloadPeerId(2)], [], limits(), CurrentDownloadLoopTick(
      0)) == CurrentDownloadLoopError.None
  assert dispatcher.tick(CurrentDownloadLoopTick(0)) == CurrentDownloadLoopError.None
  assert dispatcher.stage == CurrentDownloadLoopStage.Receiving # Capture the original current parent before the proof borrows its graph.
  let closing = owner.beginStateProof(selected, plan, policy)
  assert closing.error == StateProofAdmissionError.None
  assert dispatcher.tick(CurrentDownloadLoopTick(1)) == CurrentDownloadLoopError.None
  assert owner.stateProofActive and owner.rpc.chainPaused
  assert dispatcher.stage == CurrentDownloadLoopStage.Receiving
  dispatcher.close() # Join proof ownership before retained current ancestry/callback graph aliases retire.
  assert not owner.stateProofActive and not owner.rpc.chainPaused
  assert owner.collectStateProof(closing.value).kind == ProofWorkerCompletionKind.Uninitialized
  assert sameStateSnapshot(parent, owner.stateSnapshot.value)
proc main() {.raises.} =
  ## Genuine current roots qualify memory/durable/RPC selection, retry, deadline/cancel, shutdown and actual proof worker interaction.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, available = true)
  transfer(context)
  transfer(context, retry = true)
  transfer(context, LoopWitness.CancelDone)
  transfer(context, LoopWitness.Joined)
  transfer(context, LoopWitness.LostHandoff)
  transfer(context, disk = true)
  transfer(context, disk = true, network = true)
  transfer(context, disk = true, managed = true)
  transfer(context, disk = true, managed = true, network = true)
  proofs(context)
try:
  main()
except:
  quit(2) # Native transport, actual guest execution, proof or durable restart errors cannot satisfy adoption evidence.
echo "PVM current download loop passed"
