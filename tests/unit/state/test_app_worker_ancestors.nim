# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_worker_ancestors_arc_release"}

## Actual native worker leases span signed report discovery and resumed execution with explicit cancellation/collection barriers.
import std/assertions
import std/envvars
import std/syncio
import std/monotimes
import std/times
import std/posix/posix
import ../../../src/app/block_input as app_block_input
import ../../../src/app/candidate as app_candidate
import ../../../src/app/chain as app_chain
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/block_codec as codec_block_codec
import ../../../src/codec/header as codec_header
import ../../../src/state/report_anchors as state_report_anchors
import ../../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../support/app_candidate_context
import ../../support/testing_arc_evidence
import ../../support/state_report_admission_context as report_context

proc waitDone(worker: var PreparationWorker) =
  ## Poll only synchronized scalar state; every shared input/chain/certificate alias stays untouched until collection.
  let started = getMonoTime()
  while worker.phase != PreparationPhase.Done:
    assert (getMonoTime() - started).inSeconds < 20
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Actual work runs on the single fixed-address native worker.
proc cycle(context: SeedFixture, wire: seq[byte], older: seq[OwnedHeader], cancel: int) {.raises.} =
  ## Late cancellation at either stage never publishes or exposes a complete unwanted successor.
  var chain = initialized(context)
  var input = default(BlockInput)
  let resources = BlockInputLimits(blockBytes: ByteLimit(wire.len), ancestorBytes: ByteLimit(8192),
    ancestors: ElementLimit(1), discoverAncestors: true)
  let id = input.begin(chain, ByteLimit(wire.len), [], resources, preparationLimits()).value
  assert input.append(id, wire, true) == BlockInputError.None
  var worker = default(PreparationWorker)
  assert worker.start()
  defer: worker.close() # Join precedes input/canonical/outer fixture alias retirement on every test exit.
  let first = worker.submit(input, id, chain).value
  waitDone(worker)
  if cancel == 1:
    assert worker.cancel(first) # A Done discovery still owns its lease until collection.
  let discovered = worker.collect(first)
  assert worker.phase == PreparationPhase.Idle
  assert chain.chainView.retainedCount == 1
  if cancel == 1:
    assert discovered.kind == PreparationCompletionKind.Cancelled
    assert input.cancel(id) # Collection restored host access before suspended input retires.
    return
  assert discovered.kind == PreparationCompletionKind.Completed
  assert discovered.value.error == BlockInputError.NeedsAncestors
  assert discovered.value.ancestorDemand.missingLookups.value == 1
  assert input.stage == BlockInputStage.AwaitingAncestors
  assert worker.submit(input, id, chain).error == PreparationError.NotReady
  assert input.resumeAncestors(id, chain, older) == BlockInputError.None
  let second = worker.submit(input, id, chain).value
  assert worker.collect(first).kind == PreparationCompletionKind.Uninitialized # A stale first ticket cannot retire the resumed lease.
  waitDone(worker)
  if cancel == 2:
    assert worker.cancel(second) # Unwanted actual guest execution never becomes an adoptable collected result.
  let completed = worker.collect(second)
  assert worker.phase == PreparationPhase.Idle
  assert chain.chainView.retainedCount == 1
  if cancel == 2:
    assert completed.kind == PreparationCompletionKind.Cancelled
  else:
    assert completed.kind == PreparationCompletionKind.Completed
    assert completed.value.error == BlockInputError.None
    assert completed.value.value.finalAccumulationInfo.value.outputs.executions == 2
  assert input.stage == BlockInputStage.Idle
proc main() {.raises.} =
  ## Retain immutable signed fixture inputs across leases, touching them again only after each cycle joins.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var source = newSeq[byte](raw.len)
  for index, octet in raw: source[index] = byte(octet) # Capture the pinned independent report fixture.
  let base = decodeOwnedReport(source, 2).value
  let context = fixture(base, guarantees = 1)
  let blockOwner = candidateBlock(context)
  var wire = newSeq[byte](blockOwner.blockInfo.value.consumed)
  assert encodeOwnedBlock(blockOwner, wire).error == FrameError.None
  let older = report_context.authored(base).older
  for cancel in 0..2: cycle(context, wire, older, cancel) # Genuine success and both cancelled alternatives prime the ownership check.
  let before = getOccupiedMem()
  for index in 0..<1000: cycle(context, wire, older,
      index mod 3) # Each activation closes its actual worker before the next measurement.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("app_worker_ancestors", 1000, before, after)
  echo "worker-ancestors: ok"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Fixture/worker startup failure cannot masquerade as expected success.
except:
  quit(2)
