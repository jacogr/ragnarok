# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual native preparation preserves exact-parent authority across an exclusive ARC graph lease.

import std/assertions
import std/syncio
import std/envvars
import std/monotimes
import std/times
import std/posix/posix
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/block_input as app_block_input
import ../../../src/app/candidate as app_candidate
import ../../../src/app/chain as app_chain
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/block_codec as codec_block_codec
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/state/store as state_store
import ../../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../support/app_candidate_context
import ../../support/state_accumulation_completion_context

proc receive(input: var BlockInput, chain: ApplicationChain, wire: openArray[byte]): BlockInputId =
  ## Complete a bounded receiver before granting the exclusive worker lease.
  let admitted = input.begin(chain, ByteLimit(uint64(wire.len)), [],
    BlockInputLimits(blockBytes: ByteLimit(uint64(wire.len))), preparationLimits())
  assert admitted.error == BlockInputError.None, "admit input"
  result = admitted.value
  assert input.append(result, wire, true) == BlockInputError.None, "receive exact payload"

proc waitDone(worker: var PreparationWorker) =
  ## Poll scalar lifecycle state only; never inspect the leased chain/input or any retained alias.
  let started = getMonoTime()
  while worker.phase != PreparationPhase.Done:
    assert (getMonoTime() - started).inSeconds < 20, "bounded worker completion"
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Yield to the actual worker, with a monotonic test deadline.

proc cycle(context: SeedFixture, wire: seq[byte], cancel: bool, malformed: bool,
    lateCancel = false) {.raises.} =
  ## All fixture aliases remain alive but untouched until collection or joined close ends the lease.
  var chain = initialized(context)
  let parent = chain.stateSnapshot.value
  var input = default(BlockInput)
  var worker = default(PreparationWorker)
  var foreign = default(PreparationWorker)
  assert worker.submit(input, BlockInputId(0), chain).error == PreparationError.Closed
  assert worker.start(), "start worker"
  assert foreign.start(), "start independent idle worker"
  defer: foreign.close()
  defer: worker.close()
  assert not worker.start(), "start cannot replace a live thread"
  assert worker.submit(input, BlockInputId(0), chain).error == PreparationError.NotReady
  let id = receive(input, chain, if malformed: @[255'u8] else: wire)
  let admitted = worker.submit(input, id, chain)
  assert admitted.error == PreparationError.None, "submit ready"
  let ticket = admitted.value
  assert worker.submit(input, id, chain).error == PreparationError.Busy, "busy without graph access"
  assert not foreign.cancel(ticket), "foreign cancellation"
  assert worker.collect(default(PreparationTicket)).kind == PreparationCompletionKind.Uninitialized
  if cancel:
    assert worker.cancel(ticket), "cancellation keeps lease and slot"
  worker.waitDone()
  if lateCancel:
    assert worker.cancel(ticket), "completed cancellation retains result until collection"
  assert worker.submit(input, id, chain).error == PreparationError.Busy, "Done retains capacity"
  let completion = worker.collect(ticket)
  assert worker.phase == PreparationPhase.Idle, "collection releases slot"
  assert not worker.cancel(ticket), "collected ticket is stale"
  assert worker.collect(ticket).kind == PreparationCompletionKind.Uninitialized, "collect once"
  if cancel or lateCancel:
    assert completion.kind == PreparationCompletionKind.Cancelled, "cancel has no success"
    discard input.cancel(id) # Queued cancellation may skip preparation; lease has now ended.
  else:
    assert completion.kind == PreparationCompletionKind.Completed
    let prepared = completion.value
    if malformed:
      assert prepared.error == BlockInputError.DecodeFailure, "typed worker decode failure"
    else:
      assert prepared.error == BlockInputError.None, "genuine child execution"
      assert sameStateSnapshot(prepared.value.finalAccumulationParent.value, parent), "exact parent owner"
      assert chain.applyAccumulation(prepared.value, completionLimits().composition).error ==
        ApplicationChainError.None, "host adopts actual worker certificate"
    assert input.stage == BlockInputStage.Idle, "preparation consumed raw bytes"
  worker.close()
  worker.close() # Explicit cleanup is idempotent and default destruction is safe.
  assert worker.start(), "restart uses a new generation"
  let next = receive(input, chain, @[255'u8])
  let later = worker.submit(input, next, chain)
  assert later.error == PreparationError.None
  assert not worker.cancel(ticket), "restart cannot revive a previous ticket"
  worker.close() # Join with queued/running/completed work before input, chain and aliases retire.
  discard input.cancel(next)

proc reuse(context: SeedFixture) {.raises.} =
  ## Reuse one native thread and stable host graph through stale-ID and repeated decode-failure handoffs.
  var chain = initialized(context)
  var input = default(BlockInput)
  var worker = default(PreparationWorker)
  assert worker.start(), "start reusable worker"
  defer: worker.close()
  let id = receive(input, chain, @[255'u8])
  let wrong = worker.submit(input, BlockInputId(0), chain)
  assert wrong.error == PreparationError.None
  worker.waitDone()
  assert worker.collect(wrong.value).value.error == BlockInputError.StaleInput, "wrong input generation"
  assert input.stage == BlockInputStage.Ready, "stale generation preserves ready input"
  assert input.cancel(id), "host retires input after stale completion"
  for iteration in 0..<100:
    let current = receive(input, chain, @[255'u8])
    let admitted = worker.submit(input, current, chain)
    assert admitted.error == PreparationError.None
    worker.waitDone()
    assert worker.collect(admitted.value).value.error == BlockInputError.DecodeFailure
    assert input.stage == BlockInputStage.Idle, "reusable slot releases raw input"

proc main() {.raises.} =
  ## Signed fixture preparation executes on native workers; all canonical adoption remains on this host.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet) # Detach initialized independent fixture bytes.
  let context = fixture(decodeOwnedReport(bytes, 2).value)
  let owner = candidateBlock(context)
  var wire = newSeq[byte](owner.blockInfo.value.consumed)
  let source = Block(header: owner.blockHeader.value, extrinsic: owner.blockExtrinsic.value)
  assert encodeBlock(source, preparationLimits().reporting.admission.frame, wire).error ==
      FrameError.None
  cycle(context, wire, false, false)
  cycle(context, wire, false, true)
  cycle(context, wire, false, false, true)
  reuse(context)
  for iteration in 0..<25:
    cycle(context, wire, true, false) # Repeated real thread startup/cancellation/join releases every borrow.
  echo "Application preparation worker passed"

try:
  main() # File or thread startup failures fail the native suite.
except:
  quit(2)
