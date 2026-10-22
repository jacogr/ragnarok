# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual authenticated TLS callbacks feed distinct current sessions without hashing, with native close before genuine current execution.
import std/[assertions, envvars, syncio, monotimes, times]
import std/posix/posix
import ../../../src/app/[services, options, current_block_download, current_block_input,
  current_handoff, candidate, preparation_worker, download_schedule, chain]
import ../../../src/quic/[current_block_download_stream, current_block_download_session,
  current_block_download_peers, transport]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, report_owned]
import ../../../src/state/[store, accumulation_current_update, accumulation_current_consensus]
import ../../../src/rpc/server
import ../../support/[current_application_context, current_services_disk_samples,
  accumulation_current_chain_context, accumulation_current_candidate_context, block_download_transport]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Only native framing callbacks run while primitive hashing is refused.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe byte reception independently of any successful current preparation.
proc key(second = true): CurrentDownloadPeerKey {.raises.} =
  ## Copy exactly the expected independently generated TLS identity, never a certificate supplied by the remote.
  let raw = readFile(getEnv(if second: "RAGNAROK_TEST_PEER_B" else: "RAGNAROK_TEST_PEER_A"))
  assert raw.len == 32
  var bytes = default(array[32, byte])
  for index in 0..<32: bytes[index] = byte(raw[index])
  CurrentDownloadPeerKey(bytes)
proc scenario(context: CurrentChainFixture, mode: DownloadTransferMode, wrongKey = false,
    fragmented = false) {.raises.} =
  ## Each real connection owns its stable Services, session and peer catalog until exact native teardown.
  var path = "pvm-current-download-native-chain"
  writeFile(path, context.currentApplicationText)
  defer: discard posix.unlink(path.toCString())
  var owner = default(Services)
  var session = default(CurrentDownloadSession)
  var peers = default(CurrentDownloadPeers)
  var servers = default(DownloadResponders)
  defer:
    peers.close()
    servers.close()
    owner.close() # Catalog callbacks retire before session/receiver/canonical owners leave scope.
  var options = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain", path], options)
  assert owner.start(options, "current native download")
  let parent = owner.stateSnapshot.value
  assert peers.configure(ElementLimit(1)) == CurrentDownloadPeerError.None
  assert session.configure([DownloadPeerId(1)], DownloadScheduleLimits(peers: ElementLimit(1),
    attempts: 1, retryDelay: DownloadRetryDelay(10)), DownloadScheduleTick(100)) ==
        DownloadScheduleError.None
  let admitted = session.begin(owner, [], CurrentBlockInputLimits(blockBytes: ByteLimit(100000)),
    currentCandidateLimits(), DownloadScheduleTick(100))
  assert admitted.error == CurrentDownloadSessionError.None
  let token = admitted.value
  let request = session.request(token).value
  assert request[0] == 128 and request[1] == 37 and request[38] == 1
  for index, octet in array[32, byte](owner.chainView.bestBlock.value.blockHash):
    assert request[index+5] == octet
  let body = context.currentDiskChildBytes
  assert body.len <= high(int)-4 and uint64(body.len) <= 0xffffffff'u64
  var response = newSeq[byte](body.len+4)
  for index in 0..<4: response[index] = byte((uint64(body.len) shr (8*index)) and 255)
  for index, octet in body: response[index+4] = octet
  if mode == EmptyReply: response = @[0'u8, 0, 0, 0]
  elif mode == Oversized: response = @[255'u8, 255, 255, 255]
  assert servers.openResponders(request, response, mode)
  assert peers.openPeer(DownloadPeerId(1), key(not wrongKey), servers.port(true),
    getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000") ==
        CurrentDownloadPeerError.None
  let limits = CurrentDownloadStreamLimits(readBytes: ByteLimit(if fragmented: 1 else: 73),
    writeBytes: ByteLimit(if fragmented: 1 else: 3), timeout: CurrentDownloadTimeout(100))
  assert peers.requestStream(session, token, limits, CurrentDownloadTick(100)) ==
      CurrentDownloadPeerError.NotAuthenticated
  failHash(1)
  var requested = false
  let started = getMonoTime()
  while true:
    assert (getMonoTime()-started).inSeconds < 20, "bounded authenticated current transfer"
    assert servers.poll()
    discard peers.poll()
    if wrongKey:
      if peers.identityRejected(DownloadPeerId(1)): break
    else:
      if not requested and peers.ready(DownloadPeerId(1)):
        assert peers.requestStream(session, token, limits, CurrentDownloadTick(100)) ==
            CurrentDownloadPeerError.None
        requested = true
      if mode == NoFin and session.receivedBytes == uint64(response.len):
        assert peers.expire(CurrentDownloadTick(199)) == 0
        assert peers.expire(CurrentDownloadTick(200)) == 1
        break # The native deadline aborts without inventing a response FIN.
      if session.stage in [CurrentBlockDownloadStage.Ready, CurrentBlockDownloadStage.Empty,
          CurrentBlockDownloadStage.Failed]: break
    yieldCurrentDiskThread() # Explicit scheduler yield performs no protocol/canonical work.
  if wrongKey:
    assert not peers.ready(DownloadPeerId(1)) and not requested
  else:
    assert requested and servers.requestCount(true) == 1
    if session.streamActive:
      assert session.beginPreparation(token, owner).error ==
          CurrentDownloadSessionError.AwaitingClose
      assert session.discardInput(token).error == CurrentDownloadSessionError.AwaitingClose
  assert peers.retire(DownloadPeerId(1))
  assert not session.streamActive and not peers.busy
  assert hashCalls() == 0, "native current callbacks do no hashing or guest work"
  failHash(0)
  if mode == Healthy and not wrongKey:
    assert session.stage == CurrentBlockDownloadStage.Ready
    assert session.beginPreparation(token, owner).error == CurrentDownloadSessionError.None
    assert owner.preparationActive and owner.rpc.chainPaused
    let preparationStarted = getMonoTime()
    while owner.preparationPhase != PreparationPhase.Done:
      assert (getMonoTime()-preparationStarted).inSeconds < 20
      owner.tick(0)
      yieldCurrentDiskThread()
    assert owner.preparationActive and owner.rpc.chainPaused
    let completed = session.collectPreparation(token, owner)
    assert completed.error == CurrentDownloadSessionError.None
    assert sameStateSnapshot(parent, owner.stateSnapshot.value)
    equalCurrentDiskMap(completed.value.currentUpdateState,
        context.source.currentConsensusState.value)
    assert owner.currentAccumulationPhase == CurrentHandoffPhase.Pending
    owner.tick(0)
    assert owner.takeCurrentAccumulation().error == CurrentHandoffError.None
    assert session.finish(token, DownloadAttemptOutcome.Adopted, DownloadScheduleTick(200)).error ==
        CurrentDownloadSessionError.None
  else:
    assert sameStateSnapshot(parent, owner.stateSnapshot.value)
    assert not owner.preparationActive and owner.currentAccumulationPhase ==
        CurrentHandoffPhase.Idle
    assert session.discardInput(token).error == CurrentDownloadSessionError.None
    let outcome = if mode == EmptyReply and not wrongKey: DownloadAttemptOutcome.Empty else: DownloadAttemptOutcome.Retry
    assert session.finish(token, outcome, DownloadScheduleTick(200)).error ==
        CurrentDownloadSessionError.None
  assert session.request(token).error == CurrentDownloadSessionError.StaleAttempt
  assert not session.busy and not session.streamActive
proc main() {.raises.} =
  ## Original complete parent and exact signed current effects remain independent of the wire responder implementation.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, available = true)
  scenario(context, Healthy)
  scenario(context, Healthy, fragmented = true)
  scenario(context, EmptyReply)
  scenario(context, Oversized)
  scenario(context, NoFin)
  scenario(context, Healthy, wrongKey = true)
try:
  main()
except:
  quit(2) # Certificate, native callback, current execution and fixture errors cannot satisfy successful routing evidence.
echo "PVM current download native passed"
