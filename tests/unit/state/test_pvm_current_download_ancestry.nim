# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine current lookup demand drains native connections, resumes original input once, preserves deadlines and rejects a changed canonical parent.
import std/[assertions, envvars, syncio, monotimes, times]
import std/posix/posix
import ../../../src/app/[services, options, current_block_download, current_block_input,
  current_handoff,
  candidate, chain, download_schedule]
import ../../../src/quic/[current_block_download_loop, current_block_download_peers,
  current_block_download_session, current_block_download_stream]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header, report_owned]
import ../../../src/state/[store, report_anchors, accumulation_current_update, accumulation_current_consensus]
import ../../support/[current_application_context, current_services_disk_samples,
  accumulation_current_chain_context, accumulation_current_candidate_context, block_download_transport]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Resumption only validates/copies certified original context; it never hashes or repeats guest work.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe primitive work independently of state flags.
type AncestryWitness {.pure.} = enum ## Each authored mode preserves actual selected authority or produces a typed refusal.
  Resume, Expire, ChangedParent
proc advance(dispatcher: var CurrentDownloadLoop, servers: var DownloadResponders,
    target: CurrentDownloadLoopStage, now = 0'u64) =
  ## The caller's explicit host clock is stable while bounded actual native callbacks retire or execute.
  let started = getMonoTime()
  while dispatcher.stage != target:
    assert (getMonoTime()-started).inSeconds < 20, "bounded current ancestry stage " & $target
    assert servers.poll()
    assert dispatcher.tick(CurrentDownloadLoopTick(now)) == CurrentDownloadLoopError.None
    yieldCurrentDiskThread()
proc scenario(context: CurrentChainFixture, witness: AncestryWitness) {.raises.} =
  ## Each real signed two-guarantee response starts without required ancestry and reserves one unchanged attempt.
  var path = "pvm-current-download-ancestry-chain"
  writeFile(path, context.currentApplicationText)
  defer: discard posix.unlink(path.toCString())
  var owner = default(Services)
  var dispatcher = default(CurrentDownloadLoop)
  var servers = default(DownloadResponders)
  defer:
    dispatcher.close()
    servers.close()
    owner.close() # Every native worker and callback retires before its stable canonical owner.
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  assert owner.start(options, "current ancestry")
  let parent = owner.stateSnapshot.value
  var expected = default(array[42, byte])
  expected[0] = 128
  expected[1] = 37
  expected[38] = 1
  for index, octet in array[32, byte](owner.chainView.bestBlock.value.blockHash): expected[
      index+5] = octet
  let body = context.currentDiskChildBytes
  assert body.len <= high(int)-4 and uint64(body.len) <= 0xffffffff'u64
  var response = newSeq[byte](body.len+4)
  for index in 0..<4: response[index] = byte((uint64(body.len) shr (8*index)) and 255)
  for index, octet in body: response[index+4] = octet
  assert servers.openResponders(expected, response)
  let rawKey = readFile(getEnv("RAGNAROK_TEST_PEER_B"))
  assert rawKey.len == 32
  var key = default(array[32, byte])
  for index in 0..<32: key[index] = byte(rawKey[index])
  let input = CurrentBlockInputLimits(blockBytes: ByteLimit(100000), ancestorBytes: ByteLimit(10000),
    ancestors: ElementLimit(4), discoverAncestors: true)
  let policy = CurrentDownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1),
    attempts: 1, retryDelay: DownloadRetryDelay(10)), input: input,
        candidate: currentCandidateLimits(),
    stream: CurrentDownloadStreamLimits(readBytes: ByteLimit(73), writeBytes: ByteLimit(3),
      timeout: CurrentDownloadTimeout(50)), attemptTimeout: CurrentDownloadAttemptTimeout(100))
  assert dispatcher.configure(owner, [DownloadPeerId(2)], [], policy, CurrentDownloadLoopTick(0)) ==
      CurrentDownloadLoopError.None
  assert dispatcher.openPeer(DownloadPeerId(2), CurrentDownloadPeerKey(key), servers.port(true),
    getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000") ==
        CurrentDownloadPeerError.None
  dispatcher.advance(servers, CurrentDownloadLoopStage.AwaitingAncestors)
  assert not owner.preparationActive and owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  assert not dispatcher.completed and dispatcher.readyPeers.len == 0
  assert servers.requestCount(true) == 1
  assert sameStateSnapshot(parent, owner.stateSnapshot.value)
  let demand = dispatcher.ancestorDemand
  assert demand.error == CurrentDownloadSessionError.None
  assert demand.value.missingLookups.value > 0
  assert dispatcher.ancestorRemaining(CurrentDownloadLoopTick(0)) == 100
  assert dispatcher.ancestorRemaining(CurrentDownloadLoopTick(30)) == 70
  if witness == AncestryWitness.ChangedParent:
    let live = initApplicationChain(owner.chainView).value
    var replacement = default(CurrentBlockInput)
    let admitted = replacement.begin(live, ByteLimit(uint64(body.len)), context.older, input,
        policy.candidate)
    assert admitted.error == CurrentBlockInputError.None
    assert replacement.append(admitted.value, body, true) == CurrentBlockInputError.None
    let prepared = replacement.prepare(admitted.value, live)
    assert prepared.error == CurrentBlockInputError.None
    assert owner.enqueueCurrentAccumulation(prepared.value) == CurrentHandoffAdmission.None
    owner.tick(0)
    assert owner.takeCurrentAccumulation().error == CurrentHandoffError.None
    failHash(1)
    assert dispatcher.resumeAncestors(context.older, CurrentDownloadLoopTick(30)) ==
        CurrentDownloadLoopError.SessionFailure
    assert dispatcher.stage == CurrentDownloadLoopStage.AwaitingAncestors
    let reason = dispatcher.sessionFailure
    assert reason.error == CurrentDownloadSessionError.DownloadFailure
    assert reason.downloadFailure.error == CurrentBlockDownloadError.InputFailure
    assert reason.downloadFailure.inputError == CurrentBlockInputError.StateChanged
    assert hashCalls() == 0 and not dispatcher.completed
    failHash(0)
    equalCurrentDiskMap(owner.stateSnapshot.value, context.source.currentConsensusState.value)
  elif witness == AncestryWitness.Expire:
    assert dispatcher.ancestorRemaining(CurrentDownloadLoopTick(100)) == 0
    failHash(1)
    assert dispatcher.resumeAncestors(context.older, CurrentDownloadLoopTick(100)) ==
        CurrentDownloadLoopError.AttemptExpired
    assert dispatcher.stage == CurrentDownloadLoopStage.Failed and not dispatcher.completed
    assert hashCalls() == 0
    failHash(0)
    assert sameStateSnapshot(parent, owner.stateSnapshot.value)
  else:
    failHash(1)
    assert dispatcher.resumeAncestors([default(OwnedHeader)], CurrentDownloadLoopTick(30)) ==
        CurrentDownloadLoopError.SessionFailure
    assert dispatcher.stage == CurrentDownloadLoopStage.AwaitingAncestors
    assert dispatcher.ancestorRemaining(CurrentDownloadLoopTick(30)) == 70
    var supplied = context.older
    assert dispatcher.resumeAncestors(supplied, CurrentDownloadLoopTick(30)) ==
        CurrentDownloadLoopError.None
    for index in 0..<supplied.len: supplied[index] = default(
        OwnedHeader) # Receiver retains immutable handles independently of caller sequence backing.
    assert dispatcher.stage == CurrentDownloadLoopStage.Receiving and hashCalls() == 0
    failHash(0)
    dispatcher.advance(servers, CurrentDownloadLoopStage.Adopted, 30)
    assert dispatcher.completed and dispatcher.adoption.error == CurrentHandoffError.None
    assert servers.requestCount(true) == 1, "resumption never repeats the original block request"
    equalCurrentDiskMap(owner.stateSnapshot.value, context.source.currentConsensusState.value)
proc main() {.raises.} =
  ## Actual report lookups and original complete current state prevent fabricated discovery or resumed-prefix evidence.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, uses = 2, available = true)
  scenario(context, AncestryWitness.Resume)
  scenario(context, AncestryWitness.Expire)
  scenario(context, AncestryWitness.ChangedParent)
try:
  main()
except:
  quit(2) # Native, lookup or execution failures cannot satisfy original-context adoption evidence.
echo "PVM current download ancestry passed"
