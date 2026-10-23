# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## E2E driver repeats signed TLS downloads and uncollected deadline cancellation before real adoption.

import std/[assertions, syncio, envvars, monotimes, times, os]
import std/posix/posix
import ../../src/quic/[block_download_loop, block_download_peers, block_download_stream]
import ../../src/app/[services, options, chain, candidate, handoff, block_download,
  block_input, download_schedule, preparation_worker]
import ../../src/codec/[bounded, block_codec, report_owned]
import ../../src/state/store
import ../support/[application_candidate_context, accumulation_completion_context,
  block_download_transport, application_running_context]

const Rounds = 32 ## Fixed live workload size; no command-line reduction can satisfy the expected marker.

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield between bounded native turns without modifying the explicit protocol clock.

proc limits(running = false): DownloadLoopLimits =
  ## One request per connection and explicit finite network/execution budgets keep each round bounded.
  result = DownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1), attempts: 1,
    retryDelay: DownloadRetryDelay(10)), input: BlockInputLimits(blockBytes: ByteLimit(100000)),
    candidate: preparationLimits(), composition: completionLimits().composition,
    stream: DownloadStreamLimits(readBytes: ByteLimit(4096), writeBytes: ByteLimit(42),
      timeout: DownloadTimeout(50)), attemptTimeout: DownloadAttemptTimeout(100))

  if running:
    result.candidate = runningLimits() # Real committed loop code receives finite larger gas/step capacity.

proc lease(owner: var Services, active: bool) =
  ## Observe mutable Services after indirect dispatcher calls without retaining stale compiler flow facts.
  assert owner.preparationActive == active and owner.rpc.chainPaused == active, "managed exclusion"

proc advance(dispatcher: var BlockDownloadLoop, servers: var DownloadResponders,
    stage: DownloadLoopStage, now: uint64) =
  ## Observe a real lifecycle stage with independent monotonic test and fixed per-turn work bounds.
  let started = getMonoTime()
  var reached = false
  for turn in 0..<20000:
    assert (getMonoTime() - started).inSeconds < 20, "bounded live dispatcher progress"
    assert servers.poll(), "native responder progress"
    assert dispatcher.tick(DownloadLoopTick(now)) == DownloadLoopError.None, "native client progress"
    if dispatcher.stage == stage:
      reached = true
      break # Preserve the observed boundary before another host turn can collect or adopt.
    discard pauseMicros(1000)
  assert reached, "expected live dispatcher stage"

proc round(owner: var Services, expected: array[42, byte], frame: seq[byte],
    key: DownloadPeerKey, cancel: bool, running = false) =
  ## Fresh native endpoints share one stable canonical Services owner across the entire workload.
  let before = owner.stateSnapshot.value
  var servers = default(DownloadResponders)
  assert servers.openResponders(expected, frame), "fresh TLS listeners"
  defer: servers.close()
  var dispatcher = default(BlockDownloadLoop)
  defer: dispatcher.close() # Join before retained snapshots, responders or canonical aliases retire.
  assert dispatcher.configure(owner, [DownloadPeerId(22)], [], limits(running), DownloadLoopTick(0)) ==
    DownloadLoopError.None, "configure live round"
  assert dispatcher.openPeer(DownloadPeerId(22), key, servers.port(true),
    getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000") ==
    DownloadPeerError.None, "open authenticated peer"
  advance(dispatcher, servers, DownloadLoopStage.Preparing, 0)
  lease(owner, true)
  assert servers.requestCount(false) == 0 and servers.requestCount(true) == 1, "exact authenticated request"
  let started = getMonoTime()
  let target = if running and cancel: PreparationPhase.Running else: PreparationPhase.Done
  while owner.preparationPhase != target:
    assert not (running and cancel and owner.preparationPhase == PreparationPhase.Done), "real running preparation must be observed"
    assert (getMonoTime() - started).inSeconds < 20, "actual signed execution completes"
    assert servers.poll(), "independent server polling during execution"
    owner.tick(0) # The host drives only permitted independent work while preparation owns the graph.
    discard pauseMicros(1000)
  lease(owner, true) # Running or completed, uncollected work retains exclusion and capacity.
  if cancel:
    assert servers.unsolicited(), "actual unrelated server stream"
    for turn in 0..<32:
      assert servers.poll(), "flush paced unsolicited frames before client deadline stimulus"
      discard pauseMicros(1000) # Native QUIC pacing uses elapsed time independently of the explicit protocol tick.
    assert not servers.resetObserved, "reset not observed before catalog polling"
    if running:
      assert owner.preparationPhase == PreparationPhase.Running, "loop still running before deadline"
    assert dispatcher.tick(DownloadLoopTick(100)) == DownloadLoopError.None, "observe attempt deadline"
    assert dispatcher.stage == DownloadLoopStage.Cancelling, "deadline retains cancelling stage"
    lease(owner, true)
    for turn in 0..<8:
      assert servers.poll(), "flush real directional reset"
      if servers.resetObserved:
        break # Observe Running at actual reset delivery, not after an unnecessary fixed polling delay.
      discard pauseMicros(1000) # Permit actual UDP delivery while the client lease remains uncollected.

    assert servers.resetObserved, "native rejection before releasing the worker lease"
    if running:
      assert owner.preparationPhase == PreparationPhase.Running, "native reset progressed during running cancellation"
    advance(dispatcher, servers, DownloadLoopStage.Waiting, 100)
    lease(owner, false)
    assert dispatcher.sessionFailure.downloadFailure.error == BlockDownloadError.Cancelled, "exact cancellation reason"
    assert dispatcher.tick(DownloadLoopTick(101)) == DownloadLoopError.None, "finish exhausted attempt"
    assert dispatcher.stage == DownloadLoopStage.Exhausted and not dispatcher.completed, "cancelled attempt exhausted"
    assert owner.accumulationStage == AccumulationHandoffStage.Idle, "cancelled handoff idle"
    assert sameStateSnapshot(before, owner.stateSnapshot.value), "expired certificate never publishes"
  else:
    advance(dispatcher, servers, DownloadLoopStage.Queued, 0)
    lease(owner, false)
    assert sameStateSnapshot(before, owner.stateSnapshot.value), "collection only queues"
    assert dispatcher.tick(DownloadLoopTick(1)) == DownloadLoopError.None, "consume genuine adoption"
    assert dispatcher.stage == DownloadLoopStage.Adopted and dispatcher.completed, "final child adopted"
    assert dispatcher.adoption.error == ApplicationChainError.None, "actual host adoption"
    assert not sameStateSnapshot(before, owner.stateSnapshot.value), "only final round publishes"
  dispatcher.close()
  lease(owner, false)
  assert owner.preparationAvailable and owner.accumulationStage == AccumulationHandoffStage.Idle, "producer available after close"

proc running(expectedKey: DownloadPeerKey, base: OwnedReport) {.raises.} =
  ## A real signed gas-bounded loop keeps computation active through native progress and cancellation.
  let context = runningFixture(base)
  writeFile("download-running-chain.json", context.seed)
  defer: discard posix.unlink("download-running-chain.json")
  var selected = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain", "download-running-chain.json",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], selected), "running state options"
  var owner = default(Services)
  assert owner.start(selected, "running download"), "running canonical owner"
  defer: owner.close()
  var request = default(BlockDownload)
  let admitted = request.begin(owner, [], limits(true).input, limits(true).candidate)
  assert admitted.error == BlockDownloadError.None, "running request admission"
  let expected = request.request(admitted.value).value
  assert request.cancel(admitted.value), "running request retirement"
  round(owner, expected, context.frame, expectedKey, true,
      true) # Running cancellation retains the graph until genuine execution ends.
  round(owner, expected, context.frame, expectedKey, false,
      true) # Positive control must execute the same loop to gas exhaustion and adopt.
  assertRunningGas(owner.stateSnapshot.value) # Inspect canonical gas only after joined cleanup has ended every lease.
  echo "DOWNLOAD_RUNNING resets=1 cancelled=1 adopted=1"

proc idle(gate: string, iteration: int) {.raises.} =
  ## Publish only after round-local transports, worker and snapshots retire; wait for the OS observer.
  echo "DOWNLOAD_IDLE " & $iteration
  stdout.flushFile()
  let started = getMonoTime()
  while not fileExists(gate & "/" & $iteration):
    assert (getMonoTime() - started).inSeconds < 20, "bounded external resource observation"
    discard pauseMicros(1000) # Test-only gating parks one process without retaining a native round or graph lease.

proc main() {.raises.} =
  ## Independent signed fixture bytes drive every real native request, worker and host adoption.
  let gate = getEnv("RAGNAROK_DOWNLOAD_LOAD_GATE")
  assert gate.len > 0, "external resource observer gate required"
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet) # Preserve the pinned independent report.
  let context = fixture(decodeOwnedReport(report, 2).value)
  let blockOwner = candidateBlock(context)
  let body = blockOwner.blockInfo.value.consumed
  var frame = newSeq[byte](body + 4)
  for index in 0..<4: frame[index] = byte((uint64(body) shr (8 * index)) and 255)
  assert encodeBlock(Block(header: blockOwner.blockHeader.value,
    extrinsic: blockOwner.blockExtrinsic.value), preparationLimits().reporting.admission.frame,
    frame.toOpenArray(4, frame.high)).error == FrameError.None, "independent signed frame"
  let pin = readFile(getEnv("RAGNAROK_TEST_PEER_B"))
  assert pin.len == 32, "exact TLS public identity"
  var key = default(array[32, byte])
  for index in 0..<32: key[index] = byte(pin[index]) # Copy the exact fresh TLS identity before borrowing any graph.
  running(DownloadPeerKey(key), decodeOwnedReport(report, 2).value)
  writeFile("download-load-chain.json", context.text)
  defer: discard posix.unlink("download-load-chain.json")
  var selected = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain", "download-load-chain.json",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], selected), "explicit state options"
  var owner = default(Services)
  assert owner.start(selected, "download load"), "canonical Services startup"
  defer: owner.close()
  var request = default(BlockDownload)
  let admitted = request.begin(owner, [], limits().input, limits().candidate)
  assert admitted.error == BlockDownloadError.None, "independent request admission"
  let expected = request.request(admitted.value).value
  assert request.cancel(admitted.value), "independent request retirement"
  for iteration in 0..<Rounds:
    round(owner, expected, frame, DownloadPeerKey(key),
        true) # Each round cancels actual Done output, then joins native cleanup.
    idle(gate, iteration) # The process remains alive across every post-cleanup resource sample.
  round(owner, expected, frame, DownloadPeerKey(key),
      false) # The same canonical owner can still adopt after repeated cancellation.
  idle(gate, Rounds) # Final adoption and its joined transport cleanup are observed separately.
  echo "DOWNLOAD_LOAD cancelled=32 resets=32 adopted=1"

try:
  main() # Setup and native failures must not produce the exact successful workload marker.
except:
  quit(2)
