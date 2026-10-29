# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_download_startup_arc_release"}

## Complete startup policies and real isolated TLS responder processes exercise the production command API.

import std/[assertions, strutils, syncio, envvars, monotimes, times, os]
import std/posix/posix
import ../../../src/app/download/[policy as download_policy, command as download_command]
import ../../../src/app/[options, services]
import "../../../src/app/block/download" as block_download
import "../../../src/quic/block/download/loop" as block_download_loop
import "../../../src/quic/block/download/stream" as block_download_stream
import "../../../src/app/block/input" as block_input
import ../../../src/app/download/schedule as download_schedule
import ../../../src/codec/[bounded, block_codec, report_owned, header]
import ../../../src/lib/atomic/file as atomic_file
import ../../../src/state/store
import ../../../src/state/report/[admission as report_admission, anchors as report_anchors]
import ../../../src/app/[chain, candidate]
import ../../../src/chain/[genesis, provider]
import ../../support/report_admission_context as report_context
import ../../support/[application_candidate_context, accumulation_completion_context,
  block_download_transport, arc_evidence]

type Scenario = enum ## Each child process serves one explicitly selected wire outcome or identity pin.
  Healthy, WrongKey, MissingFin, Empty, PreparationRefusal, Fallback,
  AncestorHealthy, AncestorMissing, AncestorBroken, AncestorSuffix, AncestorDisk

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
  assert parseCanonicalOptions(arguments(port, peer, timeout), result), "valid startup options"
proc peerOptions(port: uint16, peer: string, extra: openArray[string]): Options =
  ## Additional positional pairs precede service controls, exactly as in the public CLI.
  let base = arguments(port, peer, "10000")
  var args: seq[string] = @[]
  for index in 0..<8: args.add(base[index]) # Preserve the existing single-peer prefix.
  for value in extra: args.add(value) # Malformed list shapes remain command-level refusals.
  for index in 8..<base.len: args.add(base[index]) # Service controls always follow every positional pair.
  result = default(Options)
  assert parseCanonicalOptions(args, result), "peer list option parsing"

proc peerPreflight(peer: string) {.raises.} =
  ## Refuse partial, aliased and oversized lists before touching canonical state or TLS.
  var configured = policy()
  configured.schedule.peers = ElementLimit(16)
  writeFile("download-startup-policy.conf", encodeDownloadPolicy(configured))
  assert runDownload(peerOptions(1, peer, ["2"])) == DownloadCommandResult.InvalidOptions,
    "incomplete final pair"
  for port in ["0", "01", "65536", "18446744073709551616", "-1", "x"]:
    assert runDownload(peerOptions(1, peer, [port, peer])) == DownloadCommandResult.InvalidEndpoint,
      "additional endpoint checked before native setup"
  assert runDownload(peerOptions(1, peer, ["2", peer])) == DownloadCommandResult.InvalidIdentity,
    "duplicate principal"
  assert runDownload(peerOptions(1, peer, ["2", "missing-public-pin"])) ==
      DownloadCommandResult.InvalidIdentity, "missing additional identity"
  for width in [0, 31, 33]:
    writeFile("download-startup-identity", repeat('x', width))
    assert runDownload(peerOptions(1, peer, ["2", "download-startup-identity"])) ==
        DownloadCommandResult.InvalidIdentity, "additional identity exact width"
  let other = getEnv("RAGNAROK_TEST_PEER_A")
  assert runDownload(peerOptions(1, peer, ["1", other])) == DownloadCommandResult.InvalidEndpoint,
    "duplicate endpoint"
  configured.schedule.peers = ElementLimit(1)
  writeFile("download-startup-policy.conf", encodeDownloadPolicy(configured))
  assert runDownload(peerOptions(1, peer, ["2", other])) == DownloadCommandResult.InvalidPolicy,
    "explicit policy capacity"
  configured.schedule.peers = ElementLimit(16)
  writeFile("download-startup-policy.conf", encodeDownloadPolicy(configured))
  var extra: seq[string] = @[]
  defer:
    for index in 2..17:
      var path = "download-startup-pin-" & $index
      discard posix.unlink(path.toCString()) # Every generated public pin retires even on refusal.
  for index in 2..17:
    let path = "download-startup-pin-" & $index
    writeFile(path, repeat(char(index), 32))
    extra.add(if index == 16: "65535" else: $index)
    extra.add(path)
    if index == 16:
      # All sixteen valid distinct entries reach canonical startup; an invalid seed prevents outgoing setup.
      let chain = readFile("download-startup-chain.json")
      writeFile("download-startup-chain.json", "invalid")
      assert runDownload(peerOptions(1, peer, extra)) == DownloadCommandResult.StartupFailure,
        "sixteen peers pass atomic list preflight"
      writeFile("download-startup-chain.json", chain)
  assert runDownload(peerOptions(1, peer, extra)) == DownloadCommandResult.InvalidOptions,
    "seventeenth peer refused before file or native work"

proc ancestorPreflight(peer: string) {.raises.} =
  ## Invalid ancestry cannot open listeners, create a disk path or fall through to canonical startup.
  var configured = policy()
  configured.input.ancestors = ElementLimit(1)
  configured.input.ancestorBytes = ByteLimit(100000)
  writeFile("download-startup-policy.conf", encodeDownloadPolicy(configured))
  var args = arguments(1, peer)
  for value in ["--state-storage", "disk", "--state-db", "download-ancestor-preflight.db",
      "--download-ancestor", "missing-ancestor-header"]:
    args.add(value) # The selected nonexistent file must refuse before the fresh disk startup side effect.
  var selected = default(Options)
  assert parseCanonicalOptions(args, selected)
  assert runDownload(selected) == DownloadCommandResult.InvalidAncestors
  assert not fileExists("download-ancestor-preflight.db")
  configured.input.ancestors = ElementLimit(0)
  writeFile("download-startup-policy.conf", encodeDownloadPolicy(configured))
  assert runDownload(selected) == DownloadCommandResult.InvalidPolicy
  configured.input.ancestors = ElementLimit(1)
  configured.candidate.reporting.reports.ancestors.headers = ElementLimit(1)
  writeFile("download-startup-policy.conf", encodeDownloadPolicy(configured))
  assert runDownload(selected) == DownloadCommandResult.InvalidPolicy
  writeFile("download-startup-policy.conf", encodeDownloadPolicy(policy()))

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

proc roundTrip(expected: array[42, byte], frame: seq[byte], scenario: Scenario,
    local = false) {.raises.} =
  ## A forked responder owns its TLS engines; the parent command joins its preparation worker before every later fork.
  discard posix.unlink("download-startup-stop")
  var servers = default(DownloadResponders)
  let mode = if scenario == MissingFin: NoFin else: DownloadTransferMode.Healthy
  let response = if scenario == Empty: @[0'u8, 0, 0, 0] else: frame
  assert servers.openResponders(expected, response, mode, scenario == Fallback), "real responder startup"
  let port = servers.port(true)
  let firstPort = servers.port(false)
  let child = posix.fork()
  assert int(child) >= 0, "responder process fork"
  if int(child) == 0:
    let started = getMonoTime()
    while not fileExists("download-startup-stop") and (getMonoTime() - started).inMilliseconds < 12000:
      if not servers.poll(): posix.exitnow(3) # A native failure cannot become a successful command witness.
      pause()
    let count = servers.requestCount(true)
    let firstCount = servers.requestCount(false)
    servers.close()
    writeFile("download-startup-requests", $firstCount & ":" & $count)
    posix.exitnow(0) # No copied parent ARC owner may run destructors after fork.
  servers.close() # Parent drops only its private post-fork engine/socket copies before dialing.
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var status = 0.cint
      discard posix.waitpid(child, status, 0) # Every parent failure path joins the bounded child.
  var configured = policy()
  if scenario == Fallback:
    configured.schedule.peers = ElementLimit(2)
    configured.schedule.attempts = 2 # The empty first response must consume one genuine request before retry.
  if scenario in [WrongKey, MissingFin]:
    configured.stream.timeout = DownloadTimeout(50)
    configured.attemptTimeout = DownloadAttemptTimeout(
        100) # Negative wire cases have a separate short bounded lifetime.
  elif scenario == PreparationRefusal:
    configured.candidate.execution.preimageBytes = ByteLimit(
        0) # Raw admission succeeds; real guest preparation must refuse.
  if scenario >= AncestorHealthy:
    configured.input.ancestors = ElementLimit(1)
    configured.input.ancestorBytes = ByteLimit(100000) # Explicit v1 budgets remain required for every supplied header.
  writeFile("download-startup-policy.conf", encodeDownloadPolicy(configured))
  let peer = getEnv(if scenario == WrongKey: "RAGNAROK_TEST_PEER_A" else: "RAGNAROK_TEST_PEER_B")
  var selected = options(port, peer)
  if scenario == Fallback:
    selected = peerOptions(firstPort, getEnv("RAGNAROK_TEST_PEER_A"), [$port, peer])
  if scenario >= AncestorHealthy:
    var args = arguments(port, peer)
    if local:
      args.add("--download-local-ancestors") # A one-head seed cannot invent its older lookup anchor; explicit suffix admission remains mandatory.
    if scenario != AncestorMissing:
      args.add("--download-ancestor")
      args.add(if scenario == AncestorBroken: "download-startup-ancestor-broken"
        elif scenario == AncestorSuffix: "download-startup-ancestor-suffix"
        else: "download-startup-ancestor") # Structurally valid wrong seals reach report admission; suffixes refuse before transport.
    if scenario == AncestorDisk:
      for value in ["--state-storage", "disk", "--state-db", "download-startup-ancestor.db"]:
        args.add(value) # Genuine report/guest success must wait for confirmed durable publication.
    assert parseCanonicalOptions(args, selected)
  let outcome = runDownload(selected)
  let wanted = if scenario in [Healthy, Fallback, AncestorHealthy,
      AncestorDisk]: DownloadCommandResult.Adopted
    elif scenario == AncestorSuffix: DownloadCommandResult.InvalidAncestors
    else: DownloadCommandResult.Exhausted
  assert outcome == wanted, "actual command terminal outcome"
  writeFile("download-startup-stop", "stop")
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child, "join real responder"
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0, "responder successful exit"
  let requests = readFile("download-startup-requests")
  assert requests == (if scenario in [WrongKey, AncestorSuffix]: "0:0" elif scenario ==
      Fallback: "1:1" else: "0:1"), "actual pinned target request count"

proc responseFrame(context: SeedFixture): seq[byte] =
  ## Independently encode one complete CE response from the signed fixture, without a transport verdict hook.
  let blockOwner = candidateBlock(context)
  let body = blockOwner.blockInfo.value.consumed
  result = newSeq[byte](body + 4)
  for index in 0..<4: result[index] = byte((uint64(body) shr (8 * index)) and 255)
  assert encodeBlock(Block(header: blockOwner.blockHeader.value,
      extrinsic: blockOwner.blockExtrinsic.value), preparationLimits().reporting.admission.frame,
    result.toOpenArray(4, result.high)).error == FrameError.None

proc independentRequest(): array[42, byte] {.raises.} =
  ## Fresh canonical admission derives the expected request, then retires all owners before responder forks.
  var owner = default(Services)
  defer: owner.close()
  var initial = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "download-startup-chain.json",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], initial)
  assert owner.start(initial, "test")
  var request = default(BlockDownload)
  let admitted = request.begin(owner, [], policy().input, policy().candidate)
  assert admitted.error == BlockDownloadError.None
  result = request.request(admitted.value).value
  assert request.cancel(admitted.value)

proc main() {.raises.} =
  ## Prepare a genuinely signed child/complete-map seed independently of the command's private canonical owner.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet) # Preserve every frozen report byte.
  let base = decodeOwnedReport(report, 2).value
  let context = fixture(base)
  let frame = responseFrame(context)
  writeFile("download-startup-chain.json", context.text)
  defer:
    for name in ["download-startup-chain.json", "download-startup-policy.conf",
        "download-startup-stop", "download-startup-requests", "download-startup-identity",
        "download-startup-ancestor", "download-startup-ancestor-broken",
        "download-startup-ancestor-suffix",
        "download-startup-ancestor.db"]:
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
  assert not parseCanonicalOptions(@["download"], selected), "state must be selected"
  var telemetry = arguments(1, peer)
  for control in ["--with-telemetry", "--telemetry-endpoint", "127.0.0.1:1"]:
    telemetry.add(control) # Append explicit controls without relying on unsupported sequence concatenation.
  assert not parseCanonicalOptions(telemetry, selected), "unwired outgoing telemetry refused"
  peerPreflight(peer)
  ancestorPreflight(peer)
  let expected = independentRequest()
  for scenario in Scenario.Healthy..Scenario.Fallback: roundTrip(expected, frame, scenario)
  let anchored = fixture(base, guarantees = 1)
  writeFile("download-startup-chain.json", anchored.text)
  let ancestor = report_context.authored(base).older[0]
  var wire = newSeq[byte](ancestor.headerInfo.value.consumed)
  assert encodeOwnedHeader(ancestor, wire).error == HeaderError.None
  assert replaceAtomicFile("download-startup-ancestor", wire, ByteLimit(100000)) ==
      AtomicFileError.None
  let selectedParent = initialized(anchored)
  let omitted = prepareCandidate(selectedParent, candidateBlock(anchored), [], preparationLimits())
  assert omitted.error == ApplicationCandidateError.ReportFailure
  assert omitted.reportFailure.error == ReportAdmissionError.AnchorFailure
  assert omitted.reportFailure.anchorError == ReportAnchorError.MissingLookupAnchor
  wire[wire.high] = wire[wire.high] xor 1
  let broken = decodeHeader(wire, preparationLimits().reporting.reports.ancestors.header).value.owner
  let forked = prepareCandidate(selectedParent, candidateBlock(anchored), [broken],
      preparationLimits())
  assert forked.error == ApplicationCandidateError.ReportFailure
  assert forked.reportFailure.anchorError == ReportAnchorError.BrokenAncestry
  assert replaceAtomicFile("download-startup-ancestor-broken", wire, ByteLimit(100000)) ==
      AtomicFileError.None
  wire.add(0)
  assert replaceAtomicFile("download-startup-ancestor-suffix", wire, ByteLimit(100000)) ==
      AtomicFileError.None
  let anchoredRequest = independentRequest()
  let anchoredFrame = responseFrame(anchored)
  for scenario in AncestorHealthy..AncestorDisk: roundTrip(anchoredRequest, anchoredFrame, scenario)
  for scenario in AncestorHealthy..AncestorSuffix:
    roundTrip(anchoredRequest, anchoredFrame, scenario,
        local = true) # Retain default explicit-file controls alongside the opt-in lookup witnesses.
  var reference = initialized(anchored)
  let prepared = prepareCandidate(reference, candidateBlock(anchored), [ancestor],
      preparationLimits())
  assert prepared.error == ApplicationCandidateError.None
  let expectedChild = reference.applyAccumulation(prepared.value, completionLimits().composition)
  assert expectedChild.error == ApplicationChainError.None
  var diskOptions = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "download-startup-chain.json",
    "--state-writes", "1000", "--state-write-bytes", "1000000", "--state-storage", "disk",
    "--state-db", "download-startup-ancestor.db"], diskOptions)
  var resumed = default(Services)
  assert resumed.start(diskOptions, "resume anchored download")
  assert resumed.chainView.retainedCount == 2
  let head = resumed.chainView.bestBlock.value
  assert array[32, byte](head.blockHash) == array[32, byte](expectedChild.value.blockHash)
  assert array[32, byte](head.stateSnapshot.commitment.root) == array[32, byte](
      expectedChild.value.stateSnapshot.commitment.root)
  let actualState = head.stateSnapshot
  let expectedState = expectedChild.value.stateSnapshot
  assert actualState.commitment.entries == expectedState.commitment.entries
  for index in 0..<expectedState.commitment.entries:
    let key = expectedState.keyAt(StateEntryIndex(index)).value
    assert actualState.lookup(key).value.bytes == expectedState.lookup(
        key).value.bytes # Durable restart preserves every independently composed serialized entry.
  assert resumed.chainView.parentOf(head.blockHash).error == GenesisError.None
  assert resumed.chainView.finalizedBlock.error == GenesisError.Unavailable
  resumed.close() # Restart preserves durable lookup-backed state/history without importing external finality.
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
