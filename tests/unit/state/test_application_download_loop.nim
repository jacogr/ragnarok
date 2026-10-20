# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_download_loop_arc_release"}

## Real TLS-driven dispatcher proves separate preparation/adoption turns and exact bounded retirement.

import std/[assertions, syncio, envvars]
import std/posix/posix
import ../../../src/quic/[block_download_loop, block_download_peers, block_download_stream]
import ../../../src/app/[services, options, chain, candidate, handoff, block_download,
    block_input, download_schedule, preparation_worker]
import ../../../src/codec/[bounded, block_codec, report_owned]
import ../../../src/state/[store, accumulation_finalization, accumulation_completion]
import ../../support/[application_candidate_context, accumulation_completion_context,
    block_download_transport, arc_evidence]

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield only while a real preparation worker owns execution; simulated test deadlines remain explicit.

proc peerKey(): DownloadPeerKey {.raises.} =
  ## The second responder has its own fresh certificate and exact expected public identity.
  let raw = readFile(getEnv("RAGNAROK_TEST_PEER_B"))
  assert raw.len == 32, "peerKey witness 1"
  var key = default(array[32, byte])
  for index in 0..<32: key[index] = byte(raw[index]) # Copy the complete fixture SPKI payload.
  DownloadPeerKey(key)
proc limits(attempts: uint64 = 2): DownloadLoopLimits =
  ## Every network, state-stage and adoption policy is explicitly supplied, independent of CLI defaults.
  DownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1), attempts: attempts,
    retryDelay: DownloadRetryDelay(10)), input: BlockInputLimits(blockBytes: ByteLimit(100000)),
    candidate: preparationLimits(), composition: completionLimits().composition,
    stream: DownloadStreamLimits(readBytes: ByteLimit(4096), writeBytes: ByteLimit(42),
      timeout: DownloadTimeout(50)), attemptTimeout: DownloadAttemptTimeout(100))
proc start(owner: var Services) {.raises.} =
  ## Each scenario owns an independent complete-map seed and the real Services handoff.
  var options = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain", "application-download-loop-chain.json",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], options), "start witness 1"
  assert owner.start(options, "test"), "start witness 2"
proc expected(owner: Services): array[42, byte] =
  ## Independently use the existing wire request owner to describe the responder's exact expected bytes.
  var download = default(BlockDownload)
  let admitted = download.begin(owner, [], limits().input, limits().candidate)
  assert admitted.error == BlockDownloadError.None, "expected witness 1"
  result = download.request(admitted.value).value
  assert download.cancel(admitted.value), "expected witness 2"
proc open(dispatcher: var BlockDownloadLoop, key: DownloadPeerKey,
    port: uint16): DownloadPeerError =
  ## Use the production identity callback and current explicit loopback endpoint API.
  dispatcher.openPeer(DownloadPeerId(22), key, port, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000")
proc configured(dispatcher: var BlockDownloadLoop, owner: var Services,
    policy: DownloadLoopLimits, now: uint64 = 0) =
  ## Retain stable stack owners for all following callbacks and handoff consumption.
  assert dispatcher.configure(owner, [DownloadPeerId(22)], [], policy, DownloadLoopTick(now)) ==
      DownloadLoopError.None, "configured witness 1"
proc advance(dispatcher: var BlockDownloadLoop, servers: var DownloadResponders,
    target: DownloadLoopStage, now: uint64 = 0) =
  ## Bounded polling never silently advances deadlines or substitutes a fake terminal status.
  var reached = false
  for turn in 0..<8000:
    assert servers.poll(), "advance witness 1"
    assert dispatcher.tick(DownloadLoopTick(now)) == DownloadLoopError.None, "advance witness 2"
    if dispatcher.stage == target:
      reached = true
      break # The caller inspects the real state before permitting any later dispatcher turn.
    if dispatcher.stage in [DownloadLoopStage.Preparing, DownloadLoopStage.Cancelling]:
      discard pauseMicros(1000) # A bounded test turn yields while preserving the host-supplied monotonic clock.
  if not reached:
    stderr.writeLine("Unreached stage " & $int(target) & "; actual " & $int(dispatcher.stage) &
      "; requests " & $servers.requestCount(true)) # Preserve actionable evidence for checked-release failures.
  assert reached, "advance witness 3"

proc transfer(frame: seq[byte], key: DownloadPeerKey, shutdown, lost, refuse: bool) {.raises.} =
  ## A real signed candidate must remain private through Queued and use a later Services result to complete.
  var owner = default(Services)
  start(owner)
  defer: owner.close()
  let before = owner.stateSnapshot.value
  var servers = default(DownloadResponders)
  assert servers.openResponders(expected(owner), frame), "transfer witness 1"
  defer: servers.close()
  var dispatcher = default(BlockDownloadLoop)
  defer: dispatcher.close()
  var policy = limits(1)
  if refuse: policy.composition = default(AccumulationCompositionLimits) # Valid execution followed by insufficient adoption write budgets.
  configured(dispatcher, owner, policy)
  assert dispatcher.open(key, servers.port(true)) == DownloadPeerError.None, "transfer witness 2"
  advance(dispatcher, servers, DownloadLoopStage.Queued)
  assert servers.requestCount(false) == 0 and servers.requestCount(true) == 1, "transfer witness 3"
  assert sameStateSnapshot(before, owner.stateSnapshot.value), "transfer witness 4"
  assert owner.accumulationStage == AccumulationHandoffStage.Pending and not dispatcher.completed, "transfer witness 5"
  if shutdown:
    dispatcher.close() # Closing queued work cancels rather than executing or certifying adoption.
    dispatcher.close()
    assert dispatcher.stage == DownloadLoopStage.Closed, "transfer witness 6"
    assert owner.accumulationStage == AccumulationHandoffStage.Idle, "transfer witness 7"
    assert sameStateSnapshot(before, owner.stateSnapshot.value) and not dispatcher.completed, "transfer witness 8"
  elif lost:
    assert owner.cancelAccumulation(), "transfer witness 9" # Deliberate violation of the documented exclusive Services borrow.
    assert dispatcher.tick(DownloadLoopTick(1)) == DownloadLoopError.LostHandoff, "transfer witness 10"
    assert dispatcher.stage == DownloadLoopStage.Failed and not dispatcher.completed, "transfer witness 11"
    assert sameStateSnapshot(before, owner.stateSnapshot.value), "transfer witness 12"
  else:
    assert dispatcher.tick(DownloadLoopTick(1)) == DownloadLoopError.None, "transfer witness 13"
    assert dispatcher.completed and owner.accumulationStage == AccumulationHandoffStage.Idle, "transfer witness 14"
    if refuse:
      assert dispatcher.adoption.error != ApplicationChainError.None, "transfer witness 15"
      assert dispatcher.stage == DownloadLoopStage.Waiting, "transfer witness 16"
      assert sameStateSnapshot(before, owner.stateSnapshot.value), "transfer witness 17"
      assert dispatcher.tick(DownloadLoopTick(2)) == DownloadLoopError.None, "transfer witness 18"
      assert dispatcher.stage == DownloadLoopStage.Exhausted,
          "transfer witness 19" # Actual adoption refusal consumes the bounded attempt.
    else:
      assert dispatcher.stage == DownloadLoopStage.Adopted, "transfer witness 20"
      assert dispatcher.adoption.error == ApplicationChainError.None, "transfer witness 21"
      assert not sameStateSnapshot(before, owner.stateSnapshot.value), "transfer witness 22"
      let after = owner.stateSnapshot.value
      assert dispatcher.tick(DownloadLoopTick(2)) == DownloadLoopError.None, "transfer witness 23"
      assert sameStateSnapshot(after, owner.stateSnapshot.value),
          "transfer witness 24" # Terminal turns cannot prepare/adopt again.

proc assertLease(owner: var Services, expected: bool) =
  ## Observe the mutable borrowed Services after indirect dispatcher calls, without retaining stale caller-side flow facts.
  assert owner.preparationActive == expected, "managed graph exclusion state"
  assert owner.rpc.chainPaused == expected, "RPC follows the managed graph lease"

proc preparing(frame: seq[byte], key: DownloadPeerKey, expire, shutdown: bool,
    lost = false) {.raises.} =
  ## A real retired stream lends its raw input once; network close polling and timeout cancellation retain ARC exclusion.
  var owner = default(Services)
  start(owner)
  defer: owner.close()
  let before = owner.stateSnapshot.value
  var servers = default(DownloadResponders)
  assert servers.openResponders(expected(owner), frame), "preparing responders"
  defer: servers.close()
  var dispatcher = default(BlockDownloadLoop)
  defer: dispatcher.close() # Joined worker retirement precedes every captured canonical alias.
  configured(dispatcher, owner, limits(1))
  assert dispatcher.open(key, servers.port(true)) == DownloadPeerError.None
  advance(dispatcher, servers, DownloadLoopStage.Preparing)
  assertLease(owner, true)
  assert owner.accumulationStage == AccumulationHandoffStage.Idle and not dispatcher.completed
  if shutdown:
    dispatcher.close() # No collection or adoption is needed to retire queued/running/Done execution safely.
    assertLease(owner, false)
    assert dispatcher.stage == DownloadLoopStage.Closed and not dispatcher.completed
    assert sameStateSnapshot(before, owner.stateSnapshot.value), "close never adopts private worker output"
    return
  if lost:
    owner.stopPreparation() # Deliberate violation of the exclusively borrowed producer's completion authority.
    assert dispatcher.tick(DownloadLoopTick(1)) == DownloadLoopError.LostPreparation
    assert dispatcher.stage == DownloadLoopStage.Failed and not dispatcher.completed
    dispatcher.close()
    assert sameStateSnapshot(before, owner.stateSnapshot.value), "lost worker ownership never certifies adoption"
    return
  if expire:
    assert servers.unsolicited(), "send an independent native stream while input is leased"
    assert not servers.resetObserved, "catalog has not polled/rejected the queued unsolicited stream"
    assert dispatcher.tick(DownloadLoopTick(100)) == DownloadLoopError.None
    assert dispatcher.stage == DownloadLoopStage.Cancelling
    assertLease(owner, true)
    for turn in 0..<8: assert servers.poll(), "flush actual reset response"
    assert servers.resetObserved, "dispatcher rejected a real unrelated stream before releasing its worker lease"
    assert not dispatcher.completed
    assert dispatcher.tick(DownloadLoopTick(99)) == DownloadLoopError.ClockRegression
    advance(dispatcher, servers, DownloadLoopStage.Waiting, 100)
    assertLease(owner, false)
    assert sameStateSnapshot(before, owner.stateSnapshot.value), "expired worker certificate cannot publish"
    assert dispatcher.sessionFailure.downloadFailure.error == BlockDownloadError.Cancelled
    assert dispatcher.tick(DownloadLoopTick(101)) == DownloadLoopError.None
    assert dispatcher.stage == DownloadLoopStage.Exhausted and not dispatcher.completed
  else:
    advance(dispatcher, servers, DownloadLoopStage.Queued)
    assertLease(owner, false)
    assert sameStateSnapshot(before, owner.stateSnapshot.value), "collection only queues genuine success"
    assert dispatcher.tick(DownloadLoopTick(1)) == DownloadLoopError.None
    assert dispatcher.stage == DownloadLoopStage.Adopted and dispatcher.completed
    assert not sameStateSnapshot(before, owner.stateSnapshot.value)

proc empty(key: DownloadPeerKey) {.raises.} =
  ## Empty replies retain cooldown and total attempts while keeping the same healthy authenticated endpoint.
  var owner = default(Services)
  start(owner)
  defer: owner.close()
  let before = owner.stateSnapshot.value
  var servers = default(DownloadResponders)
  assert servers.openResponders(expected(owner), @[0'u8, 0, 0, 0], EmptyReply), "empty witness 1"
  defer: servers.close()
  var dispatcher = default(BlockDownloadLoop)
  defer: dispatcher.close()
  configured(dispatcher, owner, limits())
  assert dispatcher.open(key, servers.port(true)) == DownloadPeerError.None, "empty witness 2"
  advance(dispatcher, servers, DownloadLoopStage.Receiving)
  advance(dispatcher, servers, DownloadLoopStage.Waiting)
  assert servers.requestCount(true) == 1, "empty witness 3"
  assert dispatcher.tick(DownloadLoopTick(9)) == DownloadLoopError.None, "empty witness 4"
  assert dispatcher.stage == DownloadLoopStage.Waiting, "empty witness 5"
  advance(dispatcher, servers, DownloadLoopStage.Receiving, 10)
  advance(dispatcher, servers, DownloadLoopStage.Waiting, 10)
  assert servers.requestCount(true) == 2, "empty witness 6"
  assert dispatcher.tick(DownloadLoopTick(11)) == DownloadLoopError.None, "empty witness 7"
  assert dispatcher.stage == DownloadLoopStage.Exhausted and not dispatcher.completed, "empty witness 8"
  assert sameStateSnapshot(before, owner.stateSnapshot.value), "empty witness 9"

proc deadline(key: DownloadPeerKey) {.raises.} =
  ## Missing handshakes are forcibly retired at an exact subtraction-based deadline even near uint64 maximum.
  var owner = default(Services)
  start(owner)
  defer: owner.close()
  var dispatcher = default(BlockDownloadLoop)
  defer: dispatcher.close()
  var policy = limits(1)
  policy.attemptTimeout = DownloadAttemptTimeout(5)
  let initial = high(uint64) - 10
  configured(dispatcher, owner, policy, initial)
  assert dispatcher.open(key, 1) == DownloadPeerError.None, "deadline witness 1"
  assert dispatcher.tick(DownloadLoopTick(initial)) == DownloadLoopError.None, "deadline witness 2"
  assert dispatcher.stage == DownloadLoopStage.Receiving, "deadline witness 3"
  assert dispatcher.tick(DownloadLoopTick(initial - 1)) == DownloadLoopError.ClockRegression, "deadline witness 4"
  assert dispatcher.tick(DownloadLoopTick(initial + 4)) == DownloadLoopError.None, "deadline witness 5"
  assert dispatcher.stage == DownloadLoopStage.Receiving, "deadline witness 6"
  assert dispatcher.tick(DownloadLoopTick(initial + 5)) == DownloadLoopError.None, "deadline witness 7"
  assert dispatcher.stage == DownloadLoopStage.Waiting and dispatcher.readyPeers.len == 0, "deadline witness 8"
  assert dispatcher.tick(DownloadLoopTick(initial + 6)) == DownloadLoopError.None, "deadline witness 9"
  assert dispatcher.stage == DownloadLoopStage.Exhausted and not dispatcher.completed, "deadline witness 10"

proc stalled(frame: seq[byte], key: DownloadPeerKey) {.raises.} =
  ## A complete body without response FIN cannot enter preparation and must retire at the host deadline.
  var owner = default(Services)
  start(owner)
  defer: owner.close()
  let before = owner.stateSnapshot.value
  var servers = default(DownloadResponders)
  assert servers.openResponders(expected(owner), frame, NoFin), "stalled witness 1"
  defer: servers.close()
  var dispatcher = default(BlockDownloadLoop)
  defer: dispatcher.close()
  configured(dispatcher, owner, limits(1))
  assert dispatcher.open(key, servers.port(true)) == DownloadPeerError.None, "stalled witness 2"
  advance(dispatcher, servers, DownloadLoopStage.Receiving)
  for turn in 0..<1000:
    assert servers.poll(), "stalled witness 3"
    assert dispatcher.tick(DownloadLoopTick(0)) == DownloadLoopError.None, "stalled witness 4"
  assert servers.requestCount(true) == 1 and dispatcher.stage == DownloadLoopStage.Receiving, "stalled witness 5"
  assert dispatcher.tick(DownloadLoopTick(100)) == DownloadLoopError.None, "stalled witness 6"
  assert dispatcher.stage == DownloadLoopStage.Waiting and not dispatcher.completed, "stalled witness 7"
  assert sameStateSnapshot(before, owner.stateSnapshot.value), "stalled witness 8"

proc policies(blockOwner: OwnedBlock) {.raises.} =
  ## Invalid startup inputs cannot retain Services, and another producer's handoff is never processed or taken.
  var owner = default(Services)
  var dispatcher = default(BlockDownloadLoop)
  defer: dispatcher.close()
  assert dispatcher.configure(owner, [DownloadPeerId(22)], [], limits(), DownloadLoopTick(0)) ==
      DownloadLoopError.MissingState, "policies witness 1"
  start(owner)
  defer: owner.close() # No native endpoints open in this preflight-only witness.
  var invalid = limits()
  invalid.schedule.peers = ElementLimit(17)
  assert dispatcher.configure(owner, [DownloadPeerId(22)], [], invalid, DownloadLoopTick(0)) ==
      DownloadLoopError.InvalidPolicy, "policies witness 2"
  invalid = limits()
  invalid.stream.readBytes = ByteLimit(4097)
  assert dispatcher.configure(owner, [DownloadPeerId(22)], [], invalid, DownloadLoopTick(0)) ==
      DownloadLoopError.InvalidPolicy, "policies witness 3"
  assert dispatcher.configure(owner, [DownloadPeerId(0)], [], limits(), DownloadLoopTick(0)) ==
      DownloadLoopError.InvalidPolicy, "policies witness 4"
  assert dispatcher.configure(owner, [DownloadPeerId(22), DownloadPeerId(22)], [], limits(),
    DownloadLoopTick(0)) == DownloadLoopError.InvalidPolicy, "policies witness 5"
  assert owner.enqueueCandidate(blockOwner, [], preparationLimits(), limits().composition).error ==
      ApplicationCandidateError.None, "policies witness 6"
  assert dispatcher.configure(owner, [DownloadPeerId(22)], [], limits(), DownloadLoopTick(0)) ==
      DownloadLoopError.ServicesBusy, "policies witness 7"
  assert owner.cancelAccumulation(), "policies witness 8"
  configured(dispatcher, owner, limits())
  assert owner.enqueueCandidate(blockOwner, [], preparationLimits(), limits().composition).error ==
      ApplicationCandidateError.None, "policies witness 9"
  assert dispatcher.tick(DownloadLoopTick(0)) == DownloadLoopError.ServicesBusy, "policies witness 10"
  assert owner.accumulationStage == AccumulationHandoffStage.Pending, "policies witness 11"
  owner.tick(0)
  assert dispatcher.tick(DownloadLoopTick(0)) == DownloadLoopError.ServicesBusy, "policies witness 12"
  assert owner.accumulationStage == AccumulationHandoffStage.Finished, "policies witness 13"
  dispatcher.close()
  assert owner.takeAccumulation.error == ApplicationChainError.None, "policies witness 14"

proc cycle(key: DownloadPeerKey) {.raises.} =
  ## Retire a real native dial and selected session lease before the stable Services owner leaves scope.
  var owner = default(Services)
  start(owner)
  defer: owner.close()
  var dispatcher = default(BlockDownloadLoop)
  defer: dispatcher.close()
  assert dispatcher.tick(DownloadLoopTick(0)) == DownloadLoopError.Uninitialized, "cycle witness 1"
  configured(dispatcher, owner, limits())
  assert dispatcher.configure(owner, [DownloadPeerId(22)], [], limits(), DownloadLoopTick(0)) ==
      DownloadLoopError.Busy, "cycle witness 2"
  assert dispatcher.open(key, 1) == DownloadPeerError.None, "cycle witness 3"
  assert dispatcher.tick(DownloadLoopTick(0)) == DownloadLoopError.None, "cycle witness 4"
  assert dispatcher.stage == DownloadLoopStage.Receiving, "cycle witness 5"
  dispatcher.close()
  assert dispatcher.tick(DownloadLoopTick(0)) == DownloadLoopError.Closed, "cycle witness 6"

proc main() {.raises.} =
  ## Construct an independently signed block/complete-map seed and encode its frozen CE 128 response frame.
  let key = peerKey()
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet) # Preserve the complete signed report fixture.
  let context = fixture(decodeOwnedReport(report, 2).value)
  let blockOwner = candidateBlock(context)
  let body = blockOwner.blockInfo.value.consumed
  var frame = newSeq[byte](body + 4)
  for index in 0..<4: frame[index] = byte((uint64(body) shr (8 * index)) and 255)
  assert encodeBlock(Block(header: blockOwner.blockHeader.value,
    extrinsic: blockOwner.blockExtrinsic.value), preparationLimits().reporting.admission.frame,
    frame.toOpenArray(4, frame.high)).error == FrameError.None, "main witness 1"
  writeFile("application-download-loop-chain.json", context.text)
  defer: discard posix.unlink("application-download-loop-chain.json")
  preparing(frame, key, false, false, true)
  preparing(frame, key, false, true)
  preparing(frame, key, true, false)
  preparing(frame, key, false, false)
  transfer(frame, key, true, false, false)
  transfer(frame, key, false, true, false)
  transfer(frame, key, false, false, true)
  transfer(frame, key, false, false, false)
  empty(key)
  stalled(frame, key)
  policies(blockOwner)
  deadline(key)
  cycle(key)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(key) # Release real canonical Services and composite borrowed owners on every iteration.
  let after = getOccupiedMem()
  assert before == after, "main witness 2"
  recordArcRelease("application_download_loop", 1000, before, after)
  echo "Application download loop passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # An I/O exception cannot satisfy the suite's explicit success contract.
except:
  quit(2)
