# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual native preparation preserves exact-parent authority across an exclusive ARC graph lease.

import std/[assertions, syncio, envvars, monotimes, times]
import std/posix/posix
import ../../../src/app/preparation_worker
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/app/[candidate, chain]
import "../../../src/app/block/input" as block_input
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, block_codec, report_owned]
import ../../../src/state/store
import ../../../src/state/report/admission as report_admission
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/accumulation/current/[consensus as accumulation_current_consensus,
    update as accumulation_current_update]
import ../../support/[accumulation_current_chain_context, accumulation_current_candidate_context]

proc receive(input: var CurrentBlockInput, chain: ApplicationChain, wire: openArray[
    byte]): CurrentBlockInputId =
  ## Complete a bounded receiver before granting the exclusive worker lease.
  let admitted = input.begin(chain, ByteLimit(uint64(wire.len)), [],
    CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(wire.len))), currentCandidateLimits())
  assert admitted.error == CurrentBlockInputError.None, "admit input"
  result = admitted.value
  assert input.append(result, wire, true) == CurrentBlockInputError.None, "receive exact payload"

proc waitDone(worker: var PreparationWorker) =
  ## Poll scalar lifecycle state only; never inspect the leased chain/input or any retained alias.
  let started = getMonoTime()
  while worker.phase != PreparationPhase.Done:
    assert (getMonoTime() - started).inSeconds < 20, "bounded worker completion"
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Yield to the actual worker, with a monotonic test deadline.

proc cycle(context: CurrentChainFixture, wire: seq[byte], cancel: bool, malformed: bool,
    lateCancel = false) {.raises.} =
  ## All fixture aliases remain alive but untouched until collection or joined close ends the lease.
  var chain = initApplicationChain(context.currentChainSeeded).value
  let parent = chain.stateSnapshot.value
  var input = default(CurrentBlockInput)
  var worker = default(PreparationWorker)
  var foreign = default(PreparationWorker)
  assert worker.submit(input, CurrentBlockInputId(0), chain).error == PreparationError.Closed
  assert worker.start(), "start worker"
  assert foreign.start(), "start independent idle worker"
  defer: foreign.close()
  defer: worker.close()
  assert not worker.start(), "start cannot replace a live thread"
  assert worker.submit(input, CurrentBlockInputId(0), chain).error == PreparationError.NotReady
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
    assert completion.kind == PreparationCompletionKind.CurrentCompleted
    let prepared = completion.currentValue
    if malformed:
      assert prepared.error == CurrentBlockInputError.DecodeFailure, "typed worker decode failure"
    else:
      assert prepared.error == CurrentBlockInputError.None, "genuine child execution"
      assert sameStateSnapshot(chain.stateSnapshot.value, parent), "worker cannot install the head"
      assert chain.canInstallPrepared(prepared.value), "exact original current update"
      assert array[32, byte](prepared.value.currentUpdateState.commitment.root) ==
        array[32, byte](context.source.currentConsensusState.value.commitment.root), "complete current map"
      chain.installPrepared(prepared.value) # Host-only adoption happens after collection ends every worker borrow.
    assert input.stage == CurrentBlockInputStage.Idle, "preparation consumed raw bytes"
  worker.close()
  worker.close() # Explicit cleanup is idempotent and default destruction is safe.
  assert worker.start(), "restart uses a new generation"
  let next = receive(input, chain, @[255'u8])
  let later = worker.submit(input, next, chain)
  assert later.error == PreparationError.None
  assert not worker.cancel(ticket), "restart cannot revive a previous ticket"
  worker.close() # Join with queued/running/completed work before input, chain and aliases retire.
  discard input.cancel(next)

proc reuse(context: CurrentChainFixture) {.raises.} =
  ## Reuse one native thread and stable host graph through stale-ID and repeated decode-failure handoffs.
  var chain = initApplicationChain(context.currentChainSeeded).value
  var input = default(CurrentBlockInput)
  var worker = default(PreparationWorker)
  assert worker.start(), "start reusable worker"
  defer: worker.close()
  let id = receive(input, chain, @[255'u8])
  let wrong = worker.submit(input, CurrentBlockInputId(0), chain)
  assert wrong.error == PreparationError.None
  worker.waitDone()
  assert worker.collect(wrong.value).currentValue.error == CurrentBlockInputError.StaleInput, "wrong input generation"
  assert input.stage == CurrentBlockInputStage.Ready, "stale generation preserves ready input"
  assert input.cancel(id), "host retires input after stale completion"
  for iteration in 0..<100:
    let current = receive(input, chain, @[255'u8])
    let admitted = worker.submit(input, current, chain)
    assert admitted.error == PreparationError.None
    worker.waitDone()
    assert worker.collect(admitted.value).currentValue.error == CurrentBlockInputError.DecodeFailure
    assert input.stage == CurrentBlockInputStage.Idle, "reusable slot releases raw input"

proc ancestry(context: CurrentChainFixture) {.raises.} =
  ## Two native leases retain the original current report prefix while host-side discovery supplies actual older headers.
  var chain = initApplicationChain(context.currentChainSeeded).value
  var input = default(CurrentBlockInput)
  var worker = default(PreparationWorker)
  let blockOwner = context.source.currentChainAdmission.reportBlockStage.value.value.admitted.admittedBlock
  var wire = newSeq[byte](blockOwner.blockInfo.value.consumed)
  assert blockOwner.encodeOwnedBlock(wire).error == FrameError.None
  let admitted = input.begin(chain, ByteLimit(uint64(wire.len)), [],
    CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(wire.len)), ancestorBytes: ByteLimit(10000),
      ancestors: ElementLimit(4), discoverAncestors: true), currentCandidateLimits())
  assert admitted.error == CurrentBlockInputError.None
  let id = admitted.value
  assert input.append(id, wire, true) == CurrentBlockInputError.None
  assert worker.start()
  defer: worker.close()
  let first = worker.submit(input, id, chain).value
  worker.waitDone()
  let suspended = worker.collect(first)
  assert suspended.kind == PreparationCompletionKind.CurrentCompleted
  assert suspended.currentValue.error == CurrentBlockInputError.NeedsAncestors
  assert suspended.currentValue.ancestorDemand.missingLookups.value > 0
  assert input.resumeAncestors(id, chain, context.older) == CurrentBlockInputError.None
  let second = worker.submit(input, id, chain).value
  assert not worker.cancel(first), "suspended lease ticket cannot cancel resumed work"
  worker.waitDone()
  let completed = worker.collect(second)
  assert completed.kind == PreparationCompletionKind.CurrentCompleted
  assert completed.currentValue.error == CurrentBlockInputError.None
  let prepared = completed.currentValue.value
  assert chain.canInstallPrepared(prepared)
  chain.installPrepared(prepared)
  assert array[32, byte](chain.stateSnapshot.value.commitment.root) ==
    array[32, byte](context.source.currentConsensusState.value.commitment.root)

proc alternate(context: CurrentChainFixture) {.raises.} =
  ## One fixed native thread alternates current and legacy payloads without reusing completion alternatives or stale tickets.
  var chain = initApplicationChain(context.currentChainSeeded).value
  var input = default(CurrentBlockInput)
  var legacy = default(BlockInput)
  var worker = default(PreparationWorker)
  assert worker.start()
  defer: worker.close()
  var previous = default(PreparationTicket)
  for iteration in 0..<20:
    let id = receive(input, chain, @[255'u8])
    let current = worker.submit(input, id, chain).value
    assert not worker.cancel(previous), "old payload ticket grants no authority"
    worker.waitDone()
    let done = worker.collect(current)
    assert done.kind == PreparationCompletionKind.CurrentCompleted
    assert done.currentValue.error == CurrentBlockInputError.DecodeFailure
    let started = legacy.begin(chain, ByteLimit(1), [], BlockInputLimits(blockBytes: ByteLimit(1)),
      ApplicationCandidateLimits(reporting: currentCandidateLimits().reporting))
    assert started.error == BlockInputError.None
    assert legacy.append(started.value, [255'u8], true) == BlockInputError.None
    let old = worker.submit(legacy, started.value, chain).value
    assert not worker.cancel(current), "current ticket cannot retire a later legacy payload"
    worker.waitDone()
    let legacyDone = worker.collect(old)
    assert legacyDone.kind == PreparationCompletionKind.Completed
    assert legacyDone.value.error == BlockInputError.DecodeFailure
    previous = old

proc main() {.raises.} =
  ## Signed fixture preparation executes on native workers; all canonical adoption remains on this host.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet) # Detach initialized independent fixture bytes.
  let base = decodeOwnedReport(bytes, 2).value
  let context = currentChainFixture(base, available = true)
  let owner = context.source.currentChainAdmission.reportBlockStage.value.value.admitted.admittedBlock
  var wire = newSeq[byte](owner.blockInfo.value.consumed)
  assert owner.encodeOwnedBlock(wire).error == FrameError.None
  cycle(context, wire, false, false)
  cycle(context, wire, false, true)
  cycle(context, wire, false, false, true)
  reuse(context)
  ancestry(currentChainFixture(base, uses = 2, available = true))
  alternate(context)
  for iteration in 0..<25:
    cycle(context, wire, true, false) # Repeated real thread startup/cancellation/join releases every borrow.
  echo "PVM current preparation worker passed"

try:
  main() # File or thread startup failures fail the native suite.
except:
  quit(2)
