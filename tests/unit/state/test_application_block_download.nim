# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_block_download_arc_release"}

## Independent CE 128 framing, real QUIC transfer and deferred state adoption preserve selected-head authority.

import std/[assertions, syncio, envvars]
import std/posix/posix
import "../../../src/app/block/download" as block_download
import "../../../src/app/block/input" as block_input
import ../../../src/app/[services, options, chain, candidate, handoff]
import ../../../src/app/download/schedule as download_schedule
import ../../../src/app/preparation_worker
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, block_codec, header, report_owned, assurances]
import ../../../src/state/store
import ../../../src/state/accumulation/finalization as accumulation_finalization
import ../../support/[application_candidate_context, accumulation_completion_context,
  block_download_transport, arc_evidence]

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse primitive calls during framing/native callbacks to detect accidental synchronous preparation.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Independent primitive observations distinguish actual validation from cheap byte reception.

proc resources(bytes: int): BlockInputLimits =
  ## Payload and ancestor retention ceilings are explicit caller policies, including zero ancestors.
  BlockInputLimits(blockBytes: ByteLimit(uint64(bytes)), ancestorBytes: ByteLimit(0),
      ancestors: ElementLimit(0))

proc framed(context: SeedFixture): seq[byte] =
  ## Independently frame one canonical signed block with fixed E4 size and no sequence element-count prefix.
  let owner = candidateBlock(context)
  let size = owner.blockInfo.value.consumed
  result = newSeq[byte](size + 4)
  for index in 0..<4: result[index] = byte((uint64(size) shr (8 * index)) and
      255) # Normative message framing is independent of the receiver.
  let source = Block(header: owner.blockHeader.value, extrinsic: owner.blockExtrinsic.value)
  assert encodeBlock(source, preparationLimits().reporting.admission.frame,
    result.toOpenArray(4, result.high)).error == FrameError.None

proc expectedRequest(owner: Services): array[42, byte] =
  ## Build the normative request independently: kind, E4(37), exact parent hash, ascending and E4(1).
  result = default(array[42, byte])
  result[0] = 0x80
  result[1] = 0x25
  for index, octet in array[32, byte](owner.chainView.bestBlock.value.blockHash): result[index +
      5] = octet # This identity predates reception.
  result[37] = 0
  result[38] = 1

proc begin(download: var BlockDownload, owner: Services, frame: seq[byte]): BlockDownloadId =
  ## Trusted test policy admits one payload while retaining a separately checked request generation.
  let admitted = download.begin(owner, [], resources(frame.len * 2), preparationLimits())
  assert admitted.error == BlockDownloadError.None
  admitted.value

proc fragments(owner: var Services, frame: seq[byte]) =
  ## Every split is decoded and genuinely executed after caller-buffer overwrite, without canonical publication.
  let before = owner.stateSnapshot.value
  let expected = expectedRequest(owner)
  for split in 0..frame.len:
    var download = default(BlockDownload)
    failHash(1)
    let id = download.begin(owner, frame)
    assert download.request(id).value == expected and hashCalls() == 0
    assert download.requestFinished(id) == BlockDownloadError.None
    var prefix = newSeq[byte](split)
    for index in 0..<split: prefix[index] = frame[
        index] # Each fragment is stable only for the synchronous append call.
    assert download.append(id, prefix, false) == BlockDownloadError.None
    for index in 0..<prefix.len: prefix[index] = 255 # No caller byte buffer is retained by the incremental adapter.
    assert download.stage == BlockDownloadStage.Receiving
    assert download.append(id, frame.toOpenArray(split, frame.high), true) ==
        BlockDownloadError.None
    assert download.stage == BlockDownloadStage.Ready and hashCalls() == 0
    assert download.append(id, [], true) == BlockDownloadError.Busy
    failHash(0)
    let prepared = download.enqueue(id, owner, completionLimits().composition)
    assert prepared.error == BlockDownloadError.None, "split " & $split
    assert sameStateSnapshot(prepared.value.finalAccumulationParent.value, before)
    assert owner.cancelAccumulation() # The per-split certificate is real, but this oracle intentionally cancels adoption.
    assert download.stage == BlockDownloadStage.Idle
    assert sameStateSnapshot(before, owner.stateSnapshot.value)

proc framing(owner: var Services, frame: seq[byte]) =
  ## FIN gates, zero-length sequences, malformed framing and old callback generations remain distinct.
  var download = default(BlockDownload)
  failHash(1)
  let first = download.begin(owner, frame)
  var scratch = download.request(first).value
  scratch[0] = 0
  assert download.request(first).value[0] == 128, "request extraction is a defensive fixed-array copy"
  assert download.append(first, frame, true) == BlockDownloadError.None
  assert download.stage == BlockDownloadStage.Receiving
  assert download.enqueue(first, owner, completionLimits().composition).error ==
      BlockDownloadError.NotReady
  assert download.requestFinished(first) == BlockDownloadError.None
  assert download.stage == BlockDownloadStage.Ready
  assert download.cancel(first)
  let second = download.begin(owner, frame)
  assert first != second
  assert download.append(first, frame, true) == BlockDownloadError.StaleDownload
  assert download.request(first).error == BlockDownloadError.StaleDownload
  assert download.requestFinished(first) == BlockDownloadError.StaleDownload
  assert not download.cancel(first)
  for octet in [0'u8, 0, 0, 0]:
    assert download.append(second, [octet], false) ==
        BlockDownloadError.None # A byte-at-a-time empty E4 header is still not a completed stream.
  assert download.append(second, [], true) == BlockDownloadError.None
  assert download.stage == BlockDownloadStage.Receiving
  assert download.requestFinished(second) == BlockDownloadError.None
  assert download.stage == BlockDownloadStage.Empty
  assert download.begin(owner, [], resources(frame.len), preparationLimits()).error ==
      BlockDownloadError.Busy
  assert download.enqueue(second, owner, completionLimits().composition).error ==
      BlockDownloadError.NotReady
  assert download.cancel(second)
  for cut in [0, 1, 2, 3, 4, frame.len - 1]:
    let id = download.begin(owner, frame)
    assert download.append(id, frame.toOpenArray(0, cut - 1), true) == BlockDownloadError.Truncated
    assert download.stage == BlockDownloadStage.Failed
    assert download.failure.error == BlockDownloadError.Truncated
    assert download.cancel(id) # Failed partial headers/bodies release context only after explicit acknowledgement.
  let huge = download.begin(owner, frame)
  assert download.append(huge, [255'u8, 255, 255, 255], false) == BlockDownloadError.LimitExceeded
  assert download.cancel(huge)
  var trailing = frame
  trailing.add(0)
  let extra = download.begin(owner, trailing)
  assert download.append(extra, trailing, true) == BlockDownloadError.Trailing
  assert download.cancel(extra)
  let emptyExtra = download.begin(owner, frame)
  assert download.append(emptyExtra, [0'u8, 0, 0, 0, 9], true) == BlockDownloadError.Trailing
  assert download.cancel(emptyExtra) and hashCalls() == 0
  failHash(0)

proc refusals(owner: var Services, context: SeedFixture, frame: seq[byte]) =
  ## Context preflight and exact one-block decoding keep actual typed child failures without successful prefixes.
  let chain = initApplicationChain(owner.chainView).value
  var download = default(BlockDownload)
  var missing = default(ApplicationChain)
  let policies = preparationLimits()
  failHash(1)
  assert download.begin(missing, [], resources(frame.len), policies).error ==
      BlockDownloadError.MissingHead
  assert download.begin(chain, [], resources(0), policies).error == BlockDownloadError.LimitExceeded
  var mismatch = policies
  mismatch.reporting.admission.frame.cores = CoreCount(3)
  assert download.begin(chain, [], resources(frame.len), mismatch).error ==
      BlockDownloadError.ProfileMismatch
  let parent = chain.chainView.bestBlock.value.header
  assert download.begin(chain, [parent], resources(frame.len), policies).error ==
      BlockDownloadError.LimitExceeded
  var bounded = resources(frame.len)
  bounded.ancestors = ElementLimit(1)
  assert download.begin(chain, [parent], bounded, policies).error ==
      BlockDownloadError.LimitExceeded
  bounded.ancestorBytes = ByteLimit(10000)
  assert download.begin(chain, [default(OwnedHeader)], bounded, policies).error ==
      BlockDownloadError.InvalidAncestor
  let invalid = download.begin(owner, frame)
  assert download.requestFinished(invalid) == BlockDownloadError.None
  assert download.append(invalid, [1'u8, 0, 0, 0, 1], true) == BlockDownloadError.None
  let codec = download.enqueue(invalid, owner, completionLimits().composition)
  assert codec.error == BlockDownloadError.PreparationFailure
  assert codec.failure.preparationFailure.error == BlockInputError.DecodeFailure
  assert download.failure.preparationFailure.error == BlockInputError.DecodeFailure
  assert download.cancel(invalid)
  var two = newSeq[byte]((frame.len - 4) * 2 + 4)
  let size = two.len - 4
  for index in 0..<4: two[index] = byte((uint64(size) shr (8 * index)) and
      255) # One message with two concatenated blocks still violates maximum one.
  for index in 4..<frame.len:
    two[index] = frame[index]
    two[frame.len + index - 4] = frame[index] # Encode a sequence directly, without an invented compact count.
  let multiple = download.begin(owner, two)
  assert download.requestFinished(multiple) == BlockDownloadError.None
  assert download.append(multiple, two, true) == BlockDownloadError.None
  let refused = download.enqueue(multiple, owner, completionLimits().composition)
  assert refused.failure.preparationFailure.error == BlockInputError.TrailingBytes
  assert download.cancel(multiple)
  assert hashCalls() == 0
  failHash(0)
  let unrelated = initialized(context)
  let stale = download.begin(unrelated, [], resources(frame.len), policies).value
  assert download.requestFinished(stale) == BlockDownloadError.None
  assert download.append(stale, frame, true) == BlockDownloadError.None
  failHash(1)
  let changed = download.enqueue(stale, owner, completionLimits().composition)
  assert changed.failure.preparationFailure.error == BlockInputError.StateChanged
  assert download.cancel(stale) and hashCalls() == 0
  failHash(0)

proc network(owner: var Services, frame: seq[byte]) =
  ## Native callbacks only receive bytes; the caller prepares outside poll/close and adopts on a later tick.
  var download = default(BlockDownload)
  let expected = expectedRequest(owner)
  let before = owner.stateSnapshot.value
  var schedule = default(DownloadSchedule)
  assert schedule.configure([DownloadPeerId(11)],
    DownloadScheduleLimits(peers: ElementLimit(1), attempts: 7,
      retryDelay: DownloadRetryDelay(1)), DownloadScheduleTick(0)) == DownloadScheduleError.None
  var tick = 0'u64
  for mode in [Oversized, PrematureClose, NoFin, Deadline, ResetEvent, EmptyReply, Healthy]:
    let selected = schedule.select(DownloadScheduleTick(tick))
    assert selected.error == DownloadScheduleError.None
    let attempt = selected.value
    assert attempt.peer == DownloadPeerId(11) # The fixture reuses one authenticated peer identity across transports.
    let id = download.begin(owner, frame)
    failHash(1)
    exchangeBlock(download, id, expected, frame, mode)
    assert hashCalls() == 0 and sameStateSnapshot(before, owner.stateSnapshot.value)
    failHash(0)
    if mode == Healthy:
      let queued = download.enqueue(id, owner, completionLimits().composition)
      assert queued.error == BlockDownloadError.None
      assert owner.accumulationStage == AccumulationHandoffStage.Pending
      assert sameStateSnapshot(before, owner.stateSnapshot.value)
      let pending = download.begin(owner, frame)
      assert download.requestFinished(pending) == BlockDownloadError.None
      assert download.append(pending, frame, true) == BlockDownloadError.None
      failHash(1)
      assert download.enqueue(pending, owner, completionLimits().composition).error ==
          BlockDownloadError.Busy
      assert download.stage == BlockDownloadStage.Ready and hashCalls() == 0
      failHash(0)
      owner.tick(0)
      assert owner.takeAccumulation.error == ApplicationChainError.None
      assert schedule.finish(attempt, DownloadAttemptOutcome.Adopted,
        DownloadScheduleTick(tick)) == DownloadScheduleError.None
      assert schedule.select(DownloadScheduleTick(tick)).error == DownloadScheduleError.Completed
      failHash(1)
      let stale = download.enqueue(pending, owner, completionLimits().composition)
      assert stale.failure.preparationFailure.error == BlockInputError.StateChanged
      assert hashCalls() == 0 and download.cancel(pending)
      failHash(0)
      assert owner.chainView.retainedCount == 2
    elif mode in [EmptyReply, Oversized, PrematureClose]:
      assert download.cancel(id) # The failed native frame remains observable until explicit acknowledgement.
    else:
      assert download.stage == BlockDownloadStage.Idle # Explicit unfinished-response cancellation already retired input.
    if mode != Healthy:
      let outcome = if mode == EmptyReply: DownloadAttemptOutcome.Empty else: DownloadAttemptOutcome.Retry
      assert schedule.finish(attempt, outcome, DownloadScheduleTick(tick)) ==
          DownloadScheduleError.None
    inc tick # Every retry is explicitly scheduled after the previous native callbacks retire.

proc cycle(chain: ApplicationChain, frame: seq[byte], complete: bool) =
  ## Repeated complete/partial framing releases fixed buffers and retained context without executing any guest.
  var download = default(BlockDownload)
  let id = download.begin(chain, [], resources(frame.len), preparationLimits()).value
  assert download.requestFinished(id) == BlockDownloadError.None
  if complete:
    assert download.append(id, frame, true) == BlockDownloadError.None
  else:
    assert download.append(id, frame.toOpenArray(0, 5), false) ==
        BlockDownloadError.None # A full E4 header plus body prefix owns bounded storage.
  assert download.cancel(id)

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield during bounded asynchronous preparation polling without advancing simulated protocol clocks.

proc asynchronous(frame: seq[byte], rounds: int = 2) {.raises.} =
  ## Reuse one stable worker for signed completions/cancellations, then join before releasing its graph.
  var owner = default(Services)
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain",
    "application-block-download-chain.json",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], options)
  assert owner.start(options, "async raw")
  defer: owner.close()
  let before = owner.stateSnapshot.value
  var download = default(BlockDownload)
  var previous = default(PreparationTicket)
  for iteration in 0..rounds:
    # Alternating completed jobs exercise reuse; the final outstanding job exercises joined retirement.
    let mode = if iteration == rounds: 2 else: iteration mod 2
    let admitted = download.begin(owner, [], resources(frame.len), preparationLimits())
    assert admitted.error == BlockDownloadError.None
    let id = admitted.value
    assert download.append(id, frame, true) == BlockDownloadError.None
    assert download.requestFinished(id) == BlockDownloadError.None
    let submitted = download.beginPreparation(id, owner)
    assert submitted.error == BlockDownloadError.None
    assert not owner.cancelPreparation(previous), "stale ticket cannot cancel a later raw job"
    previous = submitted.value
    assert download.stage == BlockDownloadStage.Preparing and owner.preparationActive
    assert not download.cancel(id), "ordinary cancellation cannot free leased input"
    assert download.beginPreparation(id, owner).error == BlockDownloadError.NotReady
    assert download.request(id).error == BlockDownloadError.StaleDownload
    assert download.append(id, [], true) == BlockDownloadError.StaleDownload
    assert download.enqueue(id, owner, completionLimits().composition).error ==
        BlockDownloadError.NotReady
    if mode == 2:
      assert download.retirePreparation(id, owner), "explicit retirement joins before clearing raw context"
    else:
      var done = false
      for turn in 0..<20000:
        owner.tick(0) # The managed Services gate drives only independent UI work during execution.
        if owner.preparationPhase == PreparationPhase.Done:
          done = true
          break # Preserve the uncollected graph lease for exact cancellation or completion assertions.
        discard pauseMicros(1000)
      assert done, "bounded raw worker completion"
      assert owner.preparationActive and owner.rpc.chainPaused, "Done retains graph exclusion"
      assert not owner.preparationAvailable, "completed output still owns the only worker slot"
      if mode == 1:
        assert download.cancelPreparation(id, owner), "completed cancellation discards genuine execution output"
      let completed = download.collectPreparation(id, owner, completionLimits().composition)
      if mode == 1:
        assert completed.failure.error == BlockDownloadError.Cancelled
        assert download.cancel(id)
      else:
        assert completed.error == BlockDownloadError.None
        assert sameStateSnapshot(before, completed.value.finalAccumulationParent.value)
        assert owner.accumulationStage == AccumulationHandoffStage.Pending
        assert owner.cancelAccumulation(), "test retires queued success without changing its seed"
    assert not owner.preparationActive and not owner.rpc.chainPaused
    assert owner.preparationAvailable, "collection or join restores producer admission"
    assert owner.accumulationStage == AccumulationHandoffStage.Idle
    assert sameStateSnapshot(before, owner.stateSnapshot.value)

proc main() {.raises.} =
  ## Prepare the pinned signed fixture before private lifecycle assertions and real certificate-backed streams.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet) # Independent frozen report bytes are never network input.
  let context = fixture(decodeOwnedReport(report, 2).value)
  let frame = framed(context)
  writeFile("application-block-download-chain.json", context.text)
  defer: discard posix.unlink("application-block-download-chain.json")
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain",
    "application-block-download-chain.json",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], options)
  var owner = default(Services)
  assert owner.start(options, "test")
  defer: owner.close()
  asynchronous(frame) # Retain the focused three-mode lifecycle scenario.
  asynchronous(frame, 100) # Fifty genuine certificates and fifty completed cancellations share one worker.
  fragments(owner, frame)
  framing(owner, frame)
  refusals(owner, context, frame)
  let chain = initApplicationChain(owner.chainView).value
  cycle(chain, frame, true)
  cycle(chain, frame, false)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(chain, frame, iteration mod 2 ==
      0) # Each callback owner retires before the next allocation measurement.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_block_download", 1000, before, after)
  network(owner, frame)
  echo "Application block download passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
  echo "WORKER_REUSE cycles=100 passed"

try:
  main() # Fixture/filesystem failures cannot produce a successful native-suite verdict.
except:
  quit(2)
