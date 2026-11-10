# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The real foreground node loop serves TLS state reads and retires every child before a joined command thread returns.

import std/[assertions, syncio, envvars, strutils, monotimes, times, rawthreads, atomics]
import ../../../src/app/[options, node_command, work_policy, node_work_policy, work_dispatch]
import ../../../src/jamnp-s/[work_submission, work_duty, identity]
import ../../../src/state/input_refinement
import ../../../src/app/cli/help
import ../../../src/lib/logging
import ../../../src/chain/[genesis, parameters]
import ../../../src/codec/[header, bounded]
import ../../../src/codec/state/safrole
import ../../../src/state/[store, range_proof]
import ../../../src/quic/transport
import ../../../src/jamnp-s/[read_stream, read_validation]
import ../../../src/lib/json/writer as json_writer
import ../../support/[jamnp_topology_fixture, jamnp_node_probe, jamnp_read_validation_context]
import ../../support/jamnp_node_work_policy
type RunContext = object ## Main retains stable immutable options until atomic completion and joined thread retirement.
  options: Options
  outcome: NodeCommandError
  done: cint

proc sendSignal(number: cint): cint {.importc: "raise", header: "<signal.h>".}
  ## Target only this native test process after the real foreground owner installs its handler.
let terminateSignal {.importc: "SIGTERM", header: "<signal.h>".}: cint
  ## Use the platform's real termination signal without assuming a numeric encoding.

proc run(user: pointer) {.nimcall.} =
  ## All command-owned native/ARC resources live on this thread; only a scalar publication crosses back.
  let context = cast[ptr RunContext](user)
  try: context.outcome = runNodeCommand(context.options)
  except: context.outcome = NodeCommandError.StartupFailure
  atomicStore(context.done, 1)

proc refuse(user: pointer, bytes: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Port reservation never accepts a peer or interprets external certificate bytes.
  0

proc ignore(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## The unpolled reservation has no application/native stream ownership.
  discard

proc hex(input: openArray[byte]): string =
  ## Independent canonical chainspec encoding does not use a production configuration serializer.
  result = ""
  for octet in input: result.add(toHex(int(octet), 2).toLowerAscii())

proc chainText(saved: BlockSnapshot): string =
  ## Retain the complete fixture's original opaque chapters and exact header/profile.
  var wire = newSeq[byte](saved.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(saved.header, wire).error == HeaderError.None
  var entries = JsonObject()
  for index in 0..<saved.keyCount:
    let key = saved.keyAt(StateKeyIndex(index))
    entries.add(hex(array[31, byte](key)), json(hex(saved.lookup(key).value.bytes)))
  $jsonObject([("protocol_parameters", json(hex(topologySettings().encodeParameters))),
    ("genesis_header", json(hex(wire))), ("genesis_state", json(entries))])

proc arguments(port: uint16, hash: BlockHash): seq[string] =
  ## Explicit command configuration owns paths and trusted finality, with foreground signal shutdown and a separate finite-deadline control.
  @["node", "--net-port", $port, "--net-cert", getEnv("RAGNAROK_TEST_CERT"),
    "--net-key", getEnv("RAGNAROK_TEST_KEY"), "--node-finalized", hex(array[32, byte](hash)),
    "--net-timeout-ms", "0", "--with-state", "--chain", "node-command-chain.json"]

proc captureStartup(context: nil pointer, batch: string) {.nimcall, raises: [].} =
  ## The one logger thread exclusively owns this bounded diagnostic buffer until joined close; the test reads it only afterward.
  let output = cast[ptr string](context)
  if output[].len+batch.len <= 8192: output[].add(batch)

proc startWork(options: var Options): NodeCommandError {.raises.} =
  ## Failed real startup reports the existing bounded production diagnostic without changing successful output or borrowing across logger shutdown.
  var text = ""
  var logger = default(Logger)
  assert logger.start(initLogPolicy(LogLevel.Error), captureStartup, addr text)
  defer:
    logger.close()
    options.attachLogWriter(default(LogWriter))
  options.attachLogWriter(logger.writer)
  let outcome = runNodeCommand(options)
  logger.close()
  options.attachLogWriter(default(LogWriter))
  assert outcome == NodeCommandError.Stopped, "work startup: " & $outcome & "; " & text
  outcome

proc main() {.raises.} =
  ## Independent local complete-map trust checks the response; network bytes cannot supply their own authority.
  assert nodeClock(JamCommonEraUnix-1, 6).error == NodeClockError.BeforeCommonEra
  assert nodeClock(JamCommonEraUnix, 0).error == NodeClockError.InvalidPeriod
  assert uint32(nodeClock(JamCommonEraUnix, 6).value) == 0
  assert uint32(nodeClock(JamCommonEraUnix+5, 6).value) == 0
  assert uint32(nodeClock(JamCommonEraUnix+6, 6).value) == 1
  let last = JamCommonEraUnix+int64(high(uint32))*6
  assert uint32(nodeClock(last, 6).value) == high(uint32)
  assert nodeClock(last+6, 6).error == NodeClockError.Overflow
  assert nodeClock(high(int64), 6).error == NodeClockError.Overflow
  let local = certificateIdentity(getEnv("RAGNAROK_TEST_CERT"))
  assert local.error == CertificateIdentityError.None
  var current = topologyRecords(0, 6)
  current[1].ed25519 = local.value # Actual public TLS identity must be a validator before signed distribution can be enabled.
  let saved = topologyCaptured([current, topologyRecords(1, 9), topologyRecords(2, 12)])
  writeFile("node-command-chain.json", chainText(saved.value))
  let hash = saved.value.blockHash
  let trusted = captureReadSource(saved)
  assert trusted.error == ReadVerificationError.None
  var selectedAlpn = "jamnp-s/1/"
  let digest = array[32, byte](hash)
  for index in 0..<4: selectedAlpn.add(toHex(int(digest[index]), 2).toLowerAscii())
  var reservation = default(Transport)
  var reservationContext = 0
  assert openTransport(reservation, true, false, 0, getEnv("RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), selectedAlpn, addr reservationContext, refuse, ignore)
  let port = reservation.localPort
  reservation.closeTransport() # Release the actual ephemeral port before the command claims it.
  var options = default(Options)
  var diagnostic = ""
  assert parseOptions(arguments(port, hash), options, diagnostic), diagnostic
  assert options.argumentCount == 6 and options.argument(1) == "node"
  assert options.argument(5) == hex(array[32, byte](hash))
  var defaultOptions = default(Options)
  assert parseOptions(@["node", "--with-state", "--chain", "node-command-chain.json",
    "--node-finalized", hex(array[32, byte](hash))], defaultOptions)
  assert defaultOptions.argument(6) == "0", "ordinary node lifetime defaults to foreground signal shutdown"
  assert commandHelp("node").contains("--node-finalized")
  assert commandHelp("node").contains("--node-validator-seed")
  assert not parseOptions(@["node", "--node-finalized", hex(array[32, byte](hash))], defaultOptions)
  assert not parseOptions(@["node", "--with-state"], defaultOptions)
  assert not parseOptions(@["node", "--with-state", "--node-finalized", "00"], defaultOptions)
  var rejected = default(Options)
  assert parseOptions(arguments(port, default(BlockHash)), rejected)
  assert runNodeCommand(rejected) == NodeCommandError.UnknownFinality
  var mismatch = arguments(port, hash)
  mismatch.add("--net-alpn"); mismatch.add("jamnp-s/1/deadbeef")
  assert parseOptions(mismatch, rejected)
  assert runNodeCommand(rejected) == NodeCommandError.InvalidConfig
  var finite = arguments(port, hash)
  for index in 0..<finite.len-1:
    if finite[index] == "--net-timeout-ms": finite[index+1] = "25"
  assert parseOptions(finite, rejected)
  assert runNodeCommand(rejected) == NodeCommandError.Stopped,
    "a finite monotonic deadline retires the foreground actor without inventing progress"
  var work = finite
  work.add("--node-work-policy")
  work.add("missing-node-work.policy")
  assert parseOptions(work, rejected)
  assert rejected.argumentCount == 8 and rejected.argument(7).len == 0, "policy-only node has no synthetic seed filename"
  assert rejected.argument(8) == "missing-node-work.policy"
  assert runNodeCommand(rejected) == NodeCommandError.InvalidWorkPolicy
  work[work.len-1] = "node-work.policy"
  assert parseOptions(work, rejected)
  writeFile("node-work.policy", "ragnarok-work-policy-v1\n")
  assert runNodeCommand(rejected) == NodeCommandError.InvalidWorkPolicy
  var execution = default(InputRefinementLimits)
  execution.inputBytes = ByteLimit(65536)
  writeFile("node-work.policy", encodeWorkPolicy(default(WorkSubmissionLimits), execution,
    WorkDutyLimits(chapterBytes: ByteLimit(1048576), disputeItems: ElementLimit(1023))))
  assert runNodeCommand(rejected) == NodeCommandError.Stopped
  writeFile("node-work.policy", encodeGuarantorPolicy(guarantorSettings()))
  let guarantorStartup = startWork(rejected)
  assert guarantorStartup == NodeCommandError.Stopped, "v2 foreground startup: " & $guarantorStartup
  var outsider = work
  for index in 0..<outsider.len-1:
    # A distinct actual TLS identity remains outside the configured roster; explicit v2 cannot bypass the CE135 validator-role gate.
    if outsider[index] == "--net-cert": outsider[index+1] = getEnv("RAGNAROK_TEST_CERT_B")
    elif outsider[index] == "--net-key": outsider[index+1] = getEnv("RAGNAROK_TEST_KEY_B")
  var nonvalidator = default(Options)
  assert parseOptions(outsider, nonvalidator)
  assert runNodeCommand(nonvalidator) == NodeCommandError.InvalidWorkPolicy
  assert commandHelp("node").contains("--node-work-policy")
  work.add("--node-validator-seed")
  work.add("node-work.seed")
  writeFile("node-work.seed", repeat("x", 32))
  assert parseOptions(work, rejected)
  assert rejected.argumentCount == 8 and rejected.argument(7) == "node-work.seed"
  assert rejected.argument(8) == "node-work.policy"
  let combinedStartup = startWork(rejected)
  assert combinedStartup == NodeCommandError.Stopped, "v2 plus ticket seed startup: " & $combinedStartup
  var invalidWork = finite
  invalidWork.add("--node-work-policy")
  invalidWork.add("")
  assert not parseOptions(invalidWork, rejected)
  var signing = finite
  signing.add("--node-validator-seed")
  signing.add("node-validator.seed")
  for extent in [0, 31, 33]:
    writeFile("node-validator.seed", repeat("x", extent))
    assert parseOptions(signing, rejected)
    assert rejected.argumentCount == 7 and rejected.argument(7) == "node-validator.seed"
    assert runNodeCommand(rejected) == NodeCommandError.InvalidSigner
  writeFile("node-validator.seed", repeat("x", 32))
  assert parseOptions(signing, rejected)
  assert runNodeCommand(rejected) == NodeCommandError.Stopped,
    "an explicit exact-width seed configures optional signing and still retires before foreground shutdown"
  signing[signing.len-1] = "missing-validator.seed"
  assert parseOptions(signing, rejected)
  assert runNodeCommand(rejected) == NodeCommandError.InvalidSigner
  signing[signing.len-1] = ""
  assert not parseOptions(signing, rejected)
  signing[signing.len-1] = repeat("x", 4097)
  assert not parseOptions(signing, rejected)
  assert not parseOptions(@["server", "--node-validator-seed", "node-validator.seed"], rejected)
  var context = RunContext(options: options, outcome: NodeCommandError.Uninitialized, done: 0)
  var thread = default(RawThread)
  thread.create(run, addr context)
  defer: thread.join() # The stable context and immutable options outlive every command-owned callback/worker.
  var probe = default(NodeProbe)
  defer: probe.close()
  probe.open(port, selectedAlpn)
  let deadline = getMonoTime()+initDuration(seconds = 5)
  while not probe.authenticated:
    assert getMonoTime() < deadline and atomicLoad(context.done) == 0
    probe.poll()
  var hello = @[0'u8, 37, 0, 0, 0]
  for octet in array[32, byte](hash): hello.add(octet)
  hello.add(7)
  for index in 0..<4: hello.add(0)
  let persistent = probe.issue(hello, persistent = true)
  while probe.bytes(persistent).len == 0:
    assert getMonoTime() < deadline and atomicLoad(context.done) == 0
    probe.poll()
  let request = readStateRequest(hash)
  var wire = @[129'u8, 98, 0, 0, 0]
  for octet in request.payload: wire.add(octet)
  let reading = probe.issue(wire)
  while not probe.flows[reading].receivedFin:
    assert getMonoTime() < deadline and atomicLoad(context.done) == 0
    probe.poll()
  assert not probe.flows[reading].reset
  let verified = verifyReadReply(request, probe.bytes(reading), trusted.value,
      readVerificationLimits())
  assert verified.error == ReadVerificationError.None
  assert verified.value.statePage.complete and verified.value.statePage.len == saved.value.keyCount
  assert array[32, byte](verified.value.statePage.root) == array[32, byte](saved.value.stateRoot)
  assert sendSignal(terminateSignal) == 0 # Actual signal shutdown ends the otherwise unbounded foreground command.
  while atomicLoad(context.done) == 0:
    assert getMonoTime() < deadline
    probe.poll()
  assert context.outcome == NodeCommandError.Stopped
  echo "jamnp node command: explicit finality and real TLS state service passed"
try:
  main()
except:
  quit 2 # Setup exceptions cannot substitute for actual command/TLS/cleanup evidence.
