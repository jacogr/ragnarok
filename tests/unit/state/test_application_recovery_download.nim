# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real pinned TLS acquisition executes/adopts a signed child only after independently trusted checkpoint startup succeeds.
import std/[assertions, syncio, envvars, monotimes, times, os]
import std/posix/posix
import ../../../src/app/[services, options, download_command, download_policy, download_schedule,
  block_download,
  block_input, checkpoint_identity]
import ../../../src/quic/[block_download_loop, block_download_stream]
import ../../../src/codec/[bounded, report_owned]
import ../../../src/lib/atomic_file
import ../../../src/chain/[genesis, provider]
import ../../support/application_candidate_context as candidate_context
import ../../support/accumulation_completion_context
import ../../support/[application_recovery_execution, block_download_transport]
const ChainPath = "application-recovery-download-chain"
const CheckpointPath = "application-recovery-download-map"
const TrustPath = "application-recovery-download-identity"
const HeaderPath = "application-recovery-download-header"
const PolicyPath = "application-recovery-download-policy"
const StopPath = "application-recovery-download-stop"
const CountPath = "application-recovery-download-count"
const DiskPath = "application-recovery-download.db" # Import creates this exclusively; later runs resume it without trust files.
type Scenario = enum ## Each case changes only import validity or actual guest preparation budget.
  Valid, InvalidImport, GuestRefusal, DiskInvalidImport, DiskValid, DiskExistingImport
proc pause() =
  ## Yield between bounded real responder polls without introducing a background thread.
  var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
  var remaining = default(Timespec)
  discard nanosleep(requested, remaining)
proc limits(): DownloadLoopLimits =
  ## Match existing explicit signed-child policies while independently bounding native and whole-attempt scheduling.
  DownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1), attempts: 1,
    retryDelay: DownloadRetryDelay(1)), input: BlockInputLimits(blockBytes: ByteLimit(100000)),
    candidate: candidate_context.preparationLimits(), composition: completionLimits().composition,
    stream: DownloadStreamLimits(readBytes: ByteLimit(4096), writeBytes: ByteLimit(42),
        timeout: DownloadTimeout(5000)),
    attemptTimeout: DownloadAttemptTimeout(8000))
proc selectedOptions(port: uint16, disk = false): Options =
  ## The production command receives the same complete atomic import group as the executable entry.
  result = default(Options)
  var arguments = @["download", $port, getEnv("RAGNAROK_TEST_CERT"), getEnv(
      "RAGNAROK_TEST_KEY"),
    getEnv("RAGNAROK_TEST_PEER_B"), "jamnp-s/1/00000000", "10000", PolicyPath,
    "--with-state", "--chain", ChainPath, "--state-writes", "1000", "--state-write-bytes",
        "1000000",
    "--state-checkpoint", CheckpointPath, "--state-trust", TrustPath, "--state-header", HeaderPath,
    "--state-checkpoint-bytes", "1000000"]
  if disk:
    for value in ["--state-storage", "disk", "--state-db", DiskPath]: arguments.add(value)
  assert parseCanonicalOptions(arguments, result)
proc scenario(expected: array[42, byte], frame: seq[byte], fixture: RecoveryExecutionFixture,
    mode: Scenario) {.raises.} =
  ## Each fork starts before parent command workers exist; command teardown joins them before the next fork.
  var stopFile = StopPath
  discard posix.unlink(stopFile.toCString())
  var servers = default(DownloadResponders)
  assert servers.openResponders(expected, frame)
  let port = servers.port(true)
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    let started = getMonoTime()
    while not fileExists(StopPath) and (getMonoTime() - started).inMilliseconds < 12000:
      if not servers.poll(): posix.exitnow(3) # Native responder failure cannot count as successful acquisition.
      pause()
    let count = servers.requestCount(true)
    servers.close()
    writeFile(CountPath, $count)
    posix.exitnow(0) # Never destroy copied parent ARC graphs in the child process.
  servers.close() # Drop only parent-private post-fork engine/socket copies before dialing.
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var status = 0.cint
      discard posix.waitpid(child, status, 0) # Every failure path reaps the bounded responder.
  var configured = limits()
  if mode == GuestRefusal:
    configured.candidate.execution.preimageBytes = ByteLimit(
        0) # Raw reception fits but genuine guest preparation must refuse.
  writeFile(PolicyPath, encodeDownloadPolicy(configured))
  let bytes = if mode in [InvalidImport, DiskInvalidImport]: @[255'u8] else: fixture.envelope
  assert replaceAtomicFile(CheckpointPath, bytes, ByteLimit(1000000)) == AtomicFileError.None
  let before = if mode == DiskExistingImport: readFile(DiskPath) else: ""
  let result = runDownload(selectedOptions(port, mode in [DiskInvalidImport, DiskValid,
      DiskExistingImport]))
  if mode in [Valid, DiskValid]:
    assert result == DownloadCommandResult.Adopted # Only actual deferred Services adoption grants this command result.
  elif mode in [InvalidImport, DiskInvalidImport, DiskExistingImport]:
    assert result == DownloadCommandResult.StartupFailure # Invalid imports must fail before outgoing TLS opens.
  else:
    assert result == DownloadCommandResult.Exhausted # Valid bytes/framing cannot masquerade as successful guest execution.
  writeFile(StopPath, "stop")
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0
  assert readFile(CountPath) == (if mode in [InvalidImport, DiskInvalidImport,
      DiskExistingImport]: "0" else: "1")
  if mode == DiskInvalidImport:
    assert not fileExists(DiskPath) # Failed trust/import creates no new disk database.
  elif mode == DiskExistingImport:
    assert readFile(DiskPath) == before # Import cannot replace or roll back an existing durable successor.
  elif mode == DiskValid:
    var selected = default(Options)
    assert parseCanonicalOptions(@["server", "--with-state", "--chain", ChainPath, "--state-writes",
      "1000",
      "--state-write-bytes", "1000000", "--state-storage", "disk", "--state-db", DiskPath], selected)
    var owner = default(Services)
    defer: owner.close()
    assert owner.start(selected, "resume durable downloaded child")
    assert owner.chainView.retainedCount == 2
    let childHash = owner.chainView.bestBlock.value.blockHash
    assert array[32, byte](owner.chainView.parentOf(childHash).value.blockHash) ==
      array[32, byte](fixture.expected.blockHash)
    assert owner.chainView.finalizedBlock.error == GenesisError.Unavailable
proc main() {.raises.} =
  ## A genuine signed child and independently captured import context drive all three production command outcomes.
  defer:
    for selected in [ChainPath, CheckpointPath, TrustPath, HeaderPath, PolicyPath, StopPath,
        CountPath, DiskPath]:
      var path = selected
      discard posix.unlink(path.toCString()) # No command/responder worker remains when test paths retire.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw:
    report[index] = byte(octet) # Only initialized pinned source bytes enter the fixture.
  let fixture = recoveryFixture(decodeOwnedReport(report, 2).value)
  writeFile(ChainPath, fixture.origin.text)
  let metadata = encodeApplicationCheckpointIdentity(fixture.expected, ByteLimit(238)).value
  assert replaceAtomicFile(TrustPath, metadata, ByteLimit(238)) == AtomicFileError.None
  assert replaceAtomicFile(HeaderPath, fixture.sealed, ByteLimit(300000)) == AtomicFileError.None
  let body = recoveryChildBytes(fixture)
  assert body.len > 0 and body.len <= 100000
  var frame = newSeq[byte](body.len + 4)
  for index in 0..<4:
    frame[index] = byte((uint64(body.len) shr (8 * index)) and
        255) # The proven bounded child extent fits one exact E4 frame.
  for index, octet in body:
    frame[4 + index] = octet # Fixed prefix plus proved bounded body fits the allocated response.
  var expected = default(array[42, byte])
  block:
    var owner = default(Services)
    defer: owner.close()
    startRecoveredExecution(owner, fixture, ChainPath, candidate_context.policy())
    var request = default(BlockDownload)
    let admitted = request.begin(owner, [], limits().input, limits().candidate)
    assert admitted.error == BlockDownloadError.None
    expected = request.request(admitted.value).value
    assert request.cancel(admitted.value) # No live canonical worker/listener survives into responder forks.
  for mode in low(Scenario)..high(Scenario):
    scenario(expected, frame, fixture, mode) # Each earlier command has fully retired before another responder is forked.
  echo "PASS application recovery download: real pinned TLS, genuine adoption, pre-transport import refusal and guest refusal"
try:
  main() # Native, process, trust or guest failures cannot become successful adoption.
except:
  quit(2)
