# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Production command receives a signed two-guest child before fetching only certified missing lookup context through independent TLS processes.
import std/[assertions, syncio, envvars, monotimes, times, os]
import std/posix/posix
import ../../../src/app/[download_command, download_policy, download_schedule, block_input,
    options, chain, candidate, services]
import ../../../src/quic/[block_download_loop, block_download_stream]
import ../../../src/codec/[bounded, header, block_codec, report_owned]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/[report_admission, report_anchors, store]
import ../../support/[application_candidate_context, accumulation_completion_context, block_download_transport]
import ../../support/report_admission_context as report_context

type Scenario = enum ## Each run starts a fresh bounded command and independent finite responder process.
  Healthy, Empty, WrongParent, Suffix, MissingFin, WrongPin, CountRefusal, ByteRefusal, Fallback,
    Available, InvalidChild, Durable
proc pause() =
  ## Bounded native polling yields without creating a thread or changing any protocol clock.
  var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
  var remaining = default(Timespec)
  discard nanosleep(requested, remaining)
proc frame(payload: seq[byte]): seq[byte] =
  ## Independently frame an uncounted complete GP block sequence using literal E4 bytes.
  result = newSeq[byte](payload.len + 4)
  for index in 0..<4: result[index] = byte((uint64(payload.len) shr (8 * index)) and 255)
  for index, octet in payload: result[index + 4] = octet
proc request(hash: array[32, byte], descending: bool): array[42, byte] =
  ## Expected bytes are literal, independent of both production request producers.
  result = default(array[42, byte])
  result[0] = 128
  result[1] = 37
  for index, octet in hash: result[index + 5] = octet
  result[37] = if descending: 1'u8 else: 0'u8
  result[38] = 1
proc policy(): DownloadLoopLimits =
  ## Explicit retained-header budgets are distinct from whole response and child codec ceilings.
  DownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1), attempts: 1,
    retryDelay: DownloadRetryDelay(1)), input: BlockInputLimits(blockBytes: ByteLimit(100000),
    ancestors: ElementLimit(8), ancestorBytes: ByteLimit(100000)),
    candidate: preparationLimits(), composition: completionLimits().composition,
    stream: DownloadStreamLimits(readBytes: ByteLimit(4096), writeBytes: ByteLimit(42),
      timeout: DownloadTimeout(5000)), attemptTimeout: DownloadAttemptTimeout(8000))
proc scenario(remote, child: seq[byte], remoteRequest, childRequest: array[42, byte],
    which: Scenario) {.raises.} =
  ## The responder checks child-then-remote ordering; the original child is never requested a second time.
  discard posix.unlink("discovery-command-stop")
  var response = remote
  if which == Empty: response = @[0'u8, 0, 0, 0]
  elif which == WrongParent:
    response[response.high - 7] = response[response.high -
        7] xor 1 # Change the exact historical seal without changing structural framing.
  elif which == Suffix:
    response.add(0)
    let size = response.len - 4
    for index in 0..<4: response[index] = byte((uint64(size) shr (8 * index)) and 255)
  let mode = if which == MissingFin: NoFin else: DownloadTransferMode.Healthy
  var servers = default(DownloadResponders)
  var childResponse = child
  if which == InvalidChild:
    let decoded = decodeBlock(child.toOpenArray(4, child.high), preparationLimits().reporting.admission.frame)
    assert decoded.error == FrameError.None
    let size = decoded.value.owner.blockHeader.value.readHeader.value.owner.headerInfo.value.consumed
    childResponse[size + 3] = childResponse[size +
        3] xor 1 # Corrupt the full seal while preserving all structural bytes.
  assert servers.openSequenceResponders(@[childRequest, remoteRequest], @[childResponse, response],
    @[DownloadTransferMode.Healthy, mode], which == Fallback)
  let firstPort = servers.port(false)
  let secondPort = servers.port(true)
  let process = posix.fork()
  assert int(process) >= 0
  if int(process) == 0:
    let started = getMonoTime()
    while not fileExists("discovery-command-stop") and (getMonoTime() - started).inMilliseconds < 12000:
      if not servers.poll(): posix.exitnow(3) # Real transport errors never become successful fixture observations.
      pause()
    let counts = $servers.requestCount(false) & ":" & $servers.requestCount(true)
    servers.close()
    writeFile("discovery-command-counts", counts)
    posix.exitnow(0) # Copied parent ARC owners never run destructors after fork.
  servers.close()
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(process, SIGTERM)
      var status = 0.cint
      discard posix.waitpid(process, status, 0) # Every assertion/refusal path joins the finite child.
  var limits = policy()
  if which == Fallback:
    limits.schedule.peers = ElementLimit(2)
    limits.schedule.attempts = 2
  if which == CountRefusal: limits.input.ancestors = ElementLimit(0)
  if which == ByteRefusal: limits.input.ancestorBytes = ByteLimit(0)
  if which == MissingFin: limits.stream.timeout = DownloadTimeout(100)
  writeFile("discovery-command-policy", encodeDownloadPolicy(limits))
  var args = @["download", $(if which == Fallback: firstPort else: secondPort),
    getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
    getEnv(if which in [WrongPin, Fallback]: "RAGNAROK_TEST_PEER_A" else: "RAGNAROK_TEST_PEER_B"),
    "jamnp-s/1/00000000", "10000", "discovery-command-policy"]
  if which == Fallback:
    args.add($secondPort)
    args.add(getEnv("RAGNAROK_TEST_PEER_B")) # Fallback requires independently authenticated identities.
  for value in ["--with-state", "--chain", "discovery-command-chain", "--state-writes", "1000",
      "--state-write-bytes", "1000000", "--download-discover-ancestors", "1"]:
    args.add(value)
  if which == Available:
    args.add("--download-ancestor")
    args.add("discovery-command-header") # Existing proof context must avoid every remote ancestor request.
  if which == Durable:
    for value in ["--state-storage", "disk", "--state-db", "discovery-command.db"]:
      args.add(value) # Acquisition itself writes no history; actual child adoption still waits for durable publication.
  var selected = default(Options)
  assert parseOptions(args, selected)
  let outcome = runDownloads(selected)
  let wanted = if which in [Healthy, Fallback, Available, Durable]: DownloadCommandResult.Adopted
    elif which == CountRefusal: DownloadCommandResult.InvalidPolicy
    elif which == ByteRefusal: DownloadCommandResult.Exhausted
    else: DownloadCommandResult.Exhausted
  assert outcome.error == wanted, "remote command " & $which & ": " & $outcome.error
  assert outcome.adoptedBlocks == (if which in [Healthy, Fallback, Available, Durable]: 1 else: 0)
  writeFile("discovery-command-stop", "stop")
  var status = 0.cint
  assert posix.waitpid(process, status, 0) == process and status == 0
  reaped = true
  let counts = readFile("discovery-command-counts")
  let expected = if which == Fallback: "2:2"
    elif which in [CountRefusal, WrongPin]: "0:0"
    elif which in [Available, InvalidChild]: "0:1"
    else: "0:2"
  assert counts == expected, "remote command request order/count " & $which & ": " & counts

proc main() {.raises.} =
  ## A genuine newly guaranteed report fails without its historical lookup header, then succeeds with fetched context.
  discard posix.unlink("discovery-command.db") # Repeated runner invocations begin from a fresh database even after an abrupt assertion failure.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let base = decodeOwnedReport(bytes, 2).value
  let context = fixture(base, guarantees = 1)
  writeFile("discovery-command-chain", context.text)
  defer:
    for name in ["discovery-command-chain", "discovery-command-policy", "discovery-command-stop",
        "discovery-command-counts", "discovery-command.db", "discovery-command-header"]:
      var path = name
      discard posix.unlink(path.toCString()) # Runner work directories own all generated inputs and process markers.
  let ancestor = report_context.authored(base).older[0]
  var source = initialized(context)
  let missing = prepareCandidate(source, candidateBlock(context), [], preparationLimits())
  assert missing.error == ApplicationCandidateError.ReportFailure
  assert missing.reportFailure.error == ReportAdmissionError.AnchorFailure
  assert missing.reportFailure.anchorError == ReportAnchorError.MissingLookupAnchor
  let genuine = prepareCandidate(source, candidateBlock(context), [ancestor], preparationLimits())
  assert genuine.error == ApplicationCandidateError.None
  let head = source.chainView.bestBlock.value
  var older = newSeq[byte](ancestor.headerInfo.value.consumed)
  assert encodeOwnedHeader(ancestor, older).error == HeaderError.None
  var headerFile = newString(older.len)
  for index, octet in older: headerFile[index] = char(
      octet) # The explicit-file scenario retains independently encoded complete sealed bytes.
  writeFile("discovery-command-header", headerFile)
  for octet in [0'u8, 0, 0, 0, 0, 0, 0]: older.add(
      octet) # Historical extrinsic framing is structural; only the parent-linked sealed header is retained.
  let decoded = decodeBlock(older, preparationLimits().reporting.admission.frame)
  assert decoded.error == FrameError.None and decoded.value.consumed == older.len
  let blockOwner = candidateBlock(context)
  var child = newSeq[byte](blockOwner.blockInfo.value.consumed)
  assert encodeOwnedBlock(blockOwner, child).error == FrameError.None
  let remoteRequest = request(array[32, byte](head.header.headerInfo.value.unsigned.parent), true)
  let childRequest = request(array[32, byte](head.blockHash), false)
  for which in Scenario.Healthy..Scenario.Durable:
    scenario(frame(older), frame(child), remoteRequest, childRequest,
        which) # Every command joins worker and IO lifetimes before the next process fork.
  let expected = source.applyAccumulation(genuine.value, completionLimits().composition)
  assert expected.error == ApplicationChainError.None, "independent successor retains its original canonical owner"
  var options = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain", "discovery-command-chain",
    "--state-writes", "1000", "--state-write-bytes", "1000000", "--state-storage", "disk",
    "--state-db", "discovery-command.db"], options)
  var resumed = default(Services)
  defer: resumed.close()
  assert resumed.start(options, "remote ancestry durable restart"), "normal durable restart"
  let restored = resumed.chainView
  let actual = restored.bestBlock.value
  assert restored.retainedCount == 2
  assert array[32, byte](actual.blockHash) == array[32, byte](expected.value.blockHash)
  assert array[32, byte](actual.stateSnapshot.commitment.root) == array[32, byte](
      expected.value.stateSnapshot.commitment.root)
  let actualState = actual.stateSnapshot
  let expectedState = expected.value.stateSnapshot
  assert actualState.commitment.entries == expectedState.commitment.entries
  for index in 0..<expectedState.commitment.entries:
    let key = expectedState.keyAt(StateEntryIndex(index)).value
    assert actualState.lookup(key).value.bytes == expectedState.lookup(
        key).value.bytes # Every serialized entry equals independent in-memory composition.
  assert restored.parentOf(actual.blockHash).error == GenesisError.None
  assert restored.finalizedBlock.error == GenesisError.Unavailable
  assert restored.blockAt(BlockHash(array[32, byte](head.parentHash))).error ==
      GenesisError.Unavailable # Fetched historical headers never acquire canonical snapshot/history authority.
  echo "PASS application discovery ancestor command: child-first lookup, no refetch, fallback and durable refusal"
try:
  main() # Real process/transport/admission failures retain native failure status.
except:
  quit(2)
