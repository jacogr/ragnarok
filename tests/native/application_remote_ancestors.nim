# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent TLS requests and complete durable-map witness for the actual executable's remote ancestry command.
import std/[assertions, syncio, envvars, monotimes, times, os]
import std/posix/posix
import ../../src/app/[options, services, chain, candidate, download_policy, download_schedule, block_input]
import ../../src/quic/[block_download_loop, block_download_stream]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, header, block_codec, report_owned]
import ../../src/state/[store, accumulation_finalization]
import ../support/[application_candidate_context, accumulation_completion_context, block_download_transport]
import ../support/application_download_chain
import ../support/report_admission_context as report_context

proc frame(payload: seq[byte]): seq[byte] =
  ## Encode literal CE message extent independently from the production receiver/request code.
  result = newSeq[byte](payload.len + 4)
  for index in 0..<4: result[index] = byte((uint64(payload.len) shr (index * 8)) and 255)
  for index, octet in payload: result[index + 4] = octet
proc request(hash: array[32, byte], direction: byte): array[42, byte] =
  ## Expected bytes have a fixed E4(37), exact header identity, direction and E4(1).
  result = default(array[42, byte])
  result[0] = 128
  result[1] = 37
  for index, octet in hash: result[index + 5] = octet
  result[37] = direction
  result[38] = 1
proc diskOptions(managed: bool): Options =
  ## Read the same explicit durable backend through normal startup, without remote context or trust inputs.
  var args = @["server", "--with-state", "--chain", "sequence-chain.json", "--state-writes", "1000",
    "--state-write-bytes", "1000000", "--state-storage", "disk", "--state-db", "sequence-state.db"]
  if managed:
    args.add("--state-layout")
    args.add("managed") # Physical layout never changes expected canonical history or complete-map semantics.
  result = default(Options)
  assert parseCanonicalOptions(args, result)
proc pause() =
  ## Keep the independent responder nonblocking and bounded while the production process runs.
  var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
  var remaining = default(Timespec)
  discard nanosleep(requested, remaining)
proc main() {.raises.} =
  ## Genuine report/guest preparation defines expected state without using the production command's success status.
  let mode = getEnv("RAGNAROK_REMOTE_ANCESTOR_CASE")
  let discovery = getEnv("RAGNAROK_ANCESTOR_DISCOVERY") == "1"
  assert mode in ["complete", "managed", "wrong-parent", "timeout", "sequence"]
  assert mode != "sequence" or discovery # Only child-driven acquisition exercises post-fetch successive children.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let context = fixture(decodeOwnedReport(bytes, 2).value, guarantees = 1)
  writeFile("sequence-chain.json", context.text)
  let ancestor = report_context.authored(decodeOwnedReport(bytes, 2).value).older[0]
  var source = initialized(context)
  let original = source.chainView.bestBlock.value
  let prepared = prepareCandidate(source, candidateBlock(context), [ancestor], preparationLimits())
  assert prepared.error == ApplicationCandidateError.None
  var expected = source.applyAccumulation(prepared.value, completionLimits().composition)
  assert expected.error == ApplicationChainError.None
  var limits = DownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1),
      attempts: 1,
    retryDelay: DownloadRetryDelay(1)), input: BlockInputLimits(blockBytes: ByteLimit(100000),
    ancestors: ElementLimit(8), ancestorBytes: ByteLimit(100000)), candidate: preparationLimits(),
    composition: completionLimits().composition, stream: DownloadStreamLimits(readBytes: ByteLimit(4096),
    writeBytes: ByteLimit(42), timeout: DownloadTimeout(20000)),
        attemptTimeout: DownloadAttemptTimeout(30000))
  if mode == "sequence":
    limits.composition = chainCompositionLimits() # The evolved parent legitimately has more service-statistics rows than the legacy single-child fixture.
  writeFile("sequence-policy.conf", encodeDownloadPolicy(limits))
  var historical = newSeq[byte](ancestor.headerInfo.value.consumed)
  assert encodeOwnedHeader(ancestor, historical).error == HeaderError.None
  if mode == "wrong-parent": historical[historical.high] = historical[historical.high] xor 1
  for octet in [0'u8, 0, 0, 0, 0, 0, 0]: historical.add(
      octet) # Historical extrinsics are scanned structurally; sealed header hash grants only lineage context.
  let candidate = candidateBlock(context)
  var child = newSeq[byte](candidate.blockInfo.value.consumed)
  assert encodeOwnedBlock(candidate, child).error == FrameError.None
  let remoteRequest = request(array[32, byte](original.header.headerInfo.value.unsigned.parent), 1)
  let childRequest = request(array[32, byte](original.blockHash), 0)
  var requests = @[remoteRequest, childRequest]
  var responses = @[frame(historical), frame(child)]
  let behavior = if mode == "timeout": NoFin else: DownloadTransferMode.Healthy
  var behaviors = @[behavior, DownloadTransferMode.Healthy]
  if discovery:
    requests = @[childRequest, remoteRequest]
    responses = @[frame(child), frame(historical)]
    behaviors = @[DownloadTransferMode.Healthy, behavior] # The original child must arrive before the missing-context request.
  if mode == "sequence":
    let second = signedChild(expected.value)
    let preparedSecond = prepareCandidate(source, second, [original.header, ancestor],
        preparationLimits())
    assert preparedSecond.error == ApplicationCandidateError.None,
        "second candidate preparation: " & $preparedSecond.error
    let secondRequest = request(array[32, byte](expected.value.blockHash), 0)
    expected = source.applyAccumulation(preparedSecond.value, chainCompositionLimits())
    assert expected.error == ApplicationChainError.None, "second candidate adoption: " &
        $expected.error
    var secondWire = newSeq[byte](second.blockInfo.value.consumed)
    assert encodeOwnedBlock(second, secondWire).error == FrameError.None
    requests.add(secondRequest)
    responses.add(frame(secondWire))
    behaviors.add(DownloadTransferMode.Healthy) # A fresh exact-pin child endpoint follows graceful remote endpoint retirement.
  var before = ""
  if mode == "wrong-parent":
    var seed = default(Services)
    assert seed.start(diskOptions(false), "refusal seed")
    seed.close()
    before = readFile("sequence-state.db") # Failed acquisition must preserve an already existing durable journal byte-for-byte.
  var servers = default(DownloadResponders)
  assert servers.openSequenceResponders(requests, responses, behaviors)
  writeFile("sequence-ready", $servers.port(true))
  let started = getMonoTime()
  while not fileExists("sequence-stop"):
    assert (getMonoTime() - started).inMilliseconds < 20000
    assert servers.poll()
    pause() # Native responder owns all network assertions; Python owns only process/CLI checks.
  let observedRequests = servers.requestCount(true)
  assert servers.requestCount(false) == 0
  servers.close()
  let adopted = mode in ["complete", "managed", "sequence"]
  let adoptedCount = if mode == "sequence": 2 elif adopted: 1 else: 0
  assert observedRequests == (if mode == "sequence": 3 elif adopted or discovery: 2 else: 1)
  if mode == "wrong-parent": assert readFile("sequence-state.db") == before
  var resumed = default(Services)
  defer: resumed.close()
  assert resumed.start(diskOptions(mode == "managed"), "actual executable restart")
  let view = resumed.chainView
  let actual = view.bestBlock.value
  let wanted = if adopted: expected.value else: original
  assert array[32, byte](actual.blockHash) == array[32, byte](wanted.blockHash)
  assert array[32, byte](actual.stateSnapshot.commitment.root) == array[32, byte](
      wanted.stateSnapshot.commitment.root)
  let actualState = actual.stateSnapshot
  let wantedState = wanted.stateSnapshot
  assert actualState.commitment.entries == wantedState.commitment.entries
  for index in 0..<wantedState.commitment.entries:
    let key = wantedState.keyAt(StateEntryIndex(index)).value
    assert actualState.lookup(key).value.bytes == wantedState.lookup(
        key).value.bytes # Every restored serialized entry has an independent composition witness.
  assert view.retainedCount == adoptedCount + 1
  assert view.finalizedBlock.error == GenesisError.Unavailable
  assert view.blockAt(BlockHash(array[32, byte](original.parentHash))).error ==
      GenesisError.Unavailable
  echo "REMOTE_ANCESTORS_VERIFIED adopted=" & $adoptedCount & " requests=" & $observedRequests
try:
  main() # Native/backend/protocol/assertion failures remain a nonzero independent process result.
except:
  quit(2)
