# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_download_startup_arc_release"}

## Complete startup policies and real isolated TLS responder processes exercise the production command API.

import std/[assertions, strutils, syncio, envvars, monotimes, times, os]
import std/posix/posix
import ../../../src/app/[download_policy, download_command, options, services, block_download]
import ../../../src/quic/[block_download_loop, block_download_stream]
import ../../../src/app/[block_input, download_schedule]
import ../../../src/codec/[bounded, block_codec, report_owned]
import ../../support/[application_candidate_context, accumulation_completion_context,
  block_download_transport, arc_evidence]

type Scenario = enum ## Each child process serves one explicitly selected wire outcome or identity pin.
  Healthy, WrongKey, MissingFin, Empty, PreparationRefusal

proc policy(): DownloadLoopLimits =
  ## The fixture supplies every stage policy explicitly; command pauses require independent real-time budgets.
  DownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1), attempts: 1,
    retryDelay: DownloadRetryDelay(1)), input: BlockInputLimits(blockBytes: ByteLimit(100000)),
    candidate: preparationLimits(), composition: completionLimits().composition,
    stream: DownloadStreamLimits(readBytes: ByteLimit(4096), writeBytes: ByteLimit(42),
      timeout: DownloadTimeout(5000)), attemptTimeout: DownloadAttemptTimeout(8000))
proc arguments(port: uint16, peer: string, timeout = "10000"): seq[string] =
  ## The same explicit positional/options shape is accepted by the actual application entry point.
  @["download", $port, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"), peer,
    "jamnp-s/1/00000000", timeout, "download-startup-policy.conf", "--with-state", "--chain",
    "download-startup-chain.json", "--state-writes", "1000", "--state-write-bytes", "1000000"]
proc options(port: uint16, peer: string, timeout = "10000"): Options =
  ## Failed/default command parsing cannot retain a previous valid configuration.
  result = default(Options)
  assert parseOptions(arguments(port, peer, timeout), result), "valid startup options"
proc pause() =
  ## Bounded child polling mirrors the production command's host pause without background threads.
  var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
  var remaining = default(Timespec)
  discard nanosleep(requested, remaining)

proc textPolicy(text: string) =
  ## Every declared leaf is mandatory; malformed input never exposes an earlier parsed prefix.
  let good = decodeDownloadPolicy(text)
  assert good.error == DownloadPolicyError.None, "complete policy"
  assert encodeDownloadPolicy(good.value) == text, "complete canonical round trip"
  let rows = text.splitLines()
  assert rows.len == 316, "v1 header plus 314 leaves and trailing newline"
  for missing in 1..<rows.high:
    var incomplete = rows[0] & "\n"
    for index in 1..<rows.high:
      if index != missing: incomplete.add(rows[index] & "\n") # Independently omit each mandatory key.
    let refused = decodeDownloadPolicy(incomplete)
    assert refused.error == DownloadPolicyError.MissingField, "missing field rejected"
    assert refused.fieldName == rows[missing].split('=')[0], "exact omitted field"
  let unknown = text.replace("schedule.peers=1", "schedule.unknown=1")
  assert decodeDownloadPolicy(unknown).error == DownloadPolicyError.UnknownField, "unknown field"
  assert decodeDownloadPolicy(text & "schedule.peers=1\n").error ==
      DownloadPolicyError.DuplicateField,
    "duplicate field"
  for number in ["", "-1", "+1", "01", "1.0", "1e1", "18446744073709551616", " 1", "1 "]:
    let invalid = text.replace("schedule.attempts=1", "schedule.attempts=" & number)
    assert decodeDownloadPolicy(invalid).error == DownloadPolicyError.InvalidNumber, "bad unsigned decimal"
  let maximum = text.replace("schedule.attempts=1", "schedule.attempts=18446744073709551615")
  assert decodeDownloadPolicy(maximum).value.schedule.attempts == high(uint64), "full uint64 maximum"
  let narrow = text.replace("candidate.execution.initialization.pages=5",
    "candidate.execution.initialization.pages=4294967296")
  assert narrow != text, "narrow witness replaces the actual page policy"
  assert decodeDownloadPolicy(narrow).error == DownloadPolicyError.InvalidNumber, "narrow overflow"
  for invalid in ["", "other\n", "\n", text & "not a key=1\n", text & "name=1=2\n"]:
    assert decodeDownloadPolicy(invalid).error != DownloadPolicyError.None, "bad document"
  assert decodeDownloadPolicy(text.substr(0, text.high - 1)).error == DownloadPolicyError.None,
    "optional final newline"
  assert decodeDownloadPolicy(text & "# bounded comment\n\n").error == DownloadPolicyError.None,
    "comments and blanks"
  assert decodeDownloadPolicy(repeat('x', DownloadPolicyBytes + 1)).error ==
      DownloadPolicyError.LimitExceeded,
    "preallocation input cap"

proc cycle(text: string) =
  ## Parsed policies are plain immutable copies; failed parses retain only their bounded reason.
  let decoded = decodeDownloadPolicy(text)
  assert decoded.error == DownloadPolicyError.None, "cycle successful policy"
  var copied = decoded.value
  copied.schedule.attempts = 99
  assert decoded.value.schedule.attempts == 1, "copied policy cannot mutate parsed snapshot"
  assert decodeDownloadPolicy(text & "schedule.peers=1\n").error ==
      DownloadPolicyError.DuplicateField,
    "cycle failed parse"

proc roundTrip(expected: array[42, byte], frame: seq[byte], scenario: Scenario) {.raises.} =
  ## A forked responder owns its own TLS engines; the command remains single-threaded in the parent.
  discard posix.unlink("download-startup-stop")
  var servers = default(DownloadResponders)
  let mode = if scenario == MissingFin: NoFin else: DownloadTransferMode.Healthy
  let response = if scenario == Empty: @[0'u8, 0, 0, 0] else: frame
  assert servers.openResponders(expected, response, mode), "real responder startup"
  let port = servers.port(true)
  let child = posix.fork()
  assert int(child) >= 0, "responder process fork"
  if int(child) == 0:
    let started = getMonoTime()
    while not fileExists("download-startup-stop") and (getMonoTime() - started).inMilliseconds < 12000:
      if not servers.poll(): posix.exitnow(3) # A native failure cannot become a successful command witness.
      pause()
    let count = servers.requestCount(true)
    servers.close()
    writeFile("download-startup-requests", $count)
    posix.exitnow(0) # No copied parent ARC owner may run destructors after fork.
  servers.close() # Parent drops only its private post-fork engine/socket copies before dialing.
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var status = 0.cint
      discard posix.waitpid(child, status, 0) # Every parent failure path joins the bounded child.
  var configured = policy()
  if scenario in [WrongKey, MissingFin]:
    configured.stream.timeout = DownloadTimeout(50)
    configured.attemptTimeout = DownloadAttemptTimeout(
        100) # Negative wire cases have a separate short bounded lifetime.
  elif scenario == PreparationRefusal:
    configured.candidate.execution.preimageBytes = ByteLimit(
        0) # Raw admission succeeds; real guest preparation must refuse.
  writeFile("download-startup-policy.conf", encodeDownloadPolicy(configured))
  let peer = getEnv(if scenario == WrongKey: "RAGNAROK_TEST_PEER_A" else: "RAGNAROK_TEST_PEER_B")
  let outcome = runDownload(options(port, peer))
  let wanted = if scenario == Healthy: DownloadCommandResult.Adopted else: DownloadCommandResult.Exhausted
  assert outcome == wanted, "actual command terminal outcome"
  writeFile("download-startup-stop", "stop")
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child, "join real responder"
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0, "responder successful exit"
  let requests = readFile("download-startup-requests")
  assert requests == (if scenario == WrongKey: "0" else: "1"), "actual pinned target request count"

proc main() {.raises.} =
  ## Prepare a genuinely signed child/complete-map seed independently of the command's private canonical owner.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet) # Preserve every frozen report byte.
  let context = fixture(decodeOwnedReport(report, 2).value)
  let blockOwner = candidateBlock(context)
  let body = blockOwner.blockInfo.value.consumed
  var frame = newSeq[byte](body + 4)
  for index in 0..<4: frame[index] = byte((uint64(body) shr (8 * index)) and 255)
  assert encodeBlock(Block(header: blockOwner.blockHeader.value,
      extrinsic: blockOwner.blockExtrinsic.value),
    preparationLimits().reporting.admission.frame, frame.toOpenArray(4, frame.high)).error ==
        FrameError.None,
    "independent response frame"
  writeFile("download-startup-chain.json", context.text)
  defer:
    for name in ["download-startup-chain.json", "download-startup-policy.conf",
        "download-startup-stop", "download-startup-requests", "download-startup-identity"]:
      var path = name
      discard posix.unlink(path.toCString()) # All generated files stay inside the runner's ignored work directory.
  let text = encodeDownloadPolicy(policy())
  textPolicy(text)
  writeFile("download-startup-policy.conf", text)
  assert loadDownloadPolicy("download-startup-policy.conf").error == DownloadPolicyError.None, "bounded file"
  assert loadDownloadPolicy("missing-policy.conf").error == DownloadPolicyError.FileFailure, "missing file"
  writeFile("download-startup-policy.conf", repeat('x', DownloadPolicyBytes + 1))
  assert loadDownloadPolicy("download-startup-policy.conf").error ==
      DownloadPolicyError.LimitExceeded,
    "oversized file"
  let peer = getEnv("RAGNAROK_TEST_PEER_B")
  assert runDownload(options(1, peer)) == DownloadCommandResult.InvalidPolicy, "bad policy before Services"
  writeFile("download-startup-policy.conf", text)
  writeFile("download-startup-identity", repeat('x', 33))
  assert runDownload(options(1, "download-startup-identity")) ==
      DownloadCommandResult.InvalidIdentity,
    "exact public identity width"
  assert runDownload(options(1, peer, "10")) == DownloadCommandResult.Timeout, "whole run timeout"
  var selected = default(Options)
  assert not parseOptions(@["download"], selected), "state must be selected"
  var telemetry = arguments(1, peer)
  for control in ["--with-telemetry", "--telemetry", "127.0.0.1:1"]:
    telemetry.add(control) # Append explicit controls without relying on unsupported sequence concatenation.
  assert not parseOptions(telemetry, selected), "unwired outgoing telemetry refused"
  var owner = default(Services)
  var initial = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain", "download-startup-chain.json",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], initial), "seed options"
  assert owner.start(initial, "test"), "canonical seed for independent request"
  var request = default(BlockDownload)
  let admitted = request.begin(owner, [], policy().input, policy().candidate)
  assert admitted.error == BlockDownloadError.None, "independent request admission"
  let expected = request.request(admitted.value).value
  assert request.cancel(admitted.value), "independent request retirement"
  owner.close() # No parent canonical listeners or workers remain across responder forks.
  for scenario in low(Scenario)..high(Scenario): roundTrip(expected, frame, scenario)
  cycle(text)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(text) # Complete and failed policy owners must retire without retained strings or partial snapshots.
  let after = getOccupiedMem()
  assert before == after, "policy ARC release"
  recordArcRelease("application_download_startup", 1000, before, after)
  echo "Application download startup passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # File/fixture failure cannot satisfy the explicit native success output.
except:
  quit(2)
