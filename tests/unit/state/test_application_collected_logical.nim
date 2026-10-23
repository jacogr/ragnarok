# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual preparation collection feeds bounded complete logical refresh; host installation stays explicit.
# @@Verification={"arc":"application_collected_logical_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_repeated_logical_context, current_namespace_transition_context,
    accumulation_current_candidate_context, collected_logical_context, arc_evidence]
import ../../../src/app/[current_logical, preparation_worker, current_block_input, block_input,
    candidate, chain]
import ../../../src/state/[parent_logical, current_logical, current_identities,
    current_request_keys, current_refresh_plan, current_logical_refresh, current_profile,
    current_state, current_globals, accumulation_current_update,
    accumulation_round, accumulation_queue, report_admission, block_transition, block_admission, store]
import ../../../src/codec/[bounded, report_owned]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Backend failure injection is enabled only after actual worker collection, on the host.
proc cycle(chain: ApplicationChain, completion: PreparationCompletion,
    source: SelectedLogicalParent) =
  ## Each temporary complete logical graph retires before the next measured cycle.
  let refreshed = refreshCollectedLogical(chain, completion, source, collectedLogicalTestLimits())
  assert refreshed.error == CollectedLogicalError.None
  let update = completion.currentValue.value
  assert sameStateSnapshot(refreshed.value.currentLogicalSource.value.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedUpdate.value.currentUpdateState,
      update.currentUpdateState)
proc main() {.raises.} =
  ## Only the maintained signed complete namespace fixture supplies inputs; the real worker produces every receipt.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = repeatedLogicalFixture(decodeOwnedReport(bytes, 2).value)
  let source = fixture.first.parent
  var chain = initApplicationChain(fixture.first.update.currentUpdatePriorView).value
  let original = chain.stateSnapshot.value
  let bound = fixture.first.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted
  let wire = currentWire(bound.admittedBlock)
  var input = default(CurrentBlockInput)
  var legacy = default(BlockInput)
  var worker = default(PreparationWorker)
  assert worker.start()
  defer: worker.close() # Join before source, fixture, input or chain aliases retire.
  let limits = collectedLogicalTestLimits()
  let emptyResult = default(CollectedLogicalResult)
  let emptyReceipt = default(PreparationCompletion)
  assert emptyResult.error == CollectedLogicalError.Uninitialized
  assert refreshCollectedLogical(chain, emptyReceipt, source, limits).error ==
      CollectedLogicalError.NoCompletion
  let id = receiveCurrent(input, chain, wire, fixture.first.source.older, currentCandidateLimits())
  let ticket = worker.submit(input, id, chain).value
  worker.waitPreparationDone()
  assert worker.collect(default(PreparationTicket)).kind == PreparationCompletionKind.Uninitialized
  assert worker.phase == PreparationPhase.Done # Wrong collection cannot authorize source access.
  let completion = worker.collect(ticket)
  assert completion.kind == PreparationCompletionKind.CurrentCompleted
  assert completion.currentValue.error == CurrentBlockInputError.None
  let refreshed = refreshCollectedLogical(chain, completion, source, limits)
  assert refreshed.error == CollectedLogicalError.None
  assert sameStateSnapshot(chain.stateSnapshot.value, original), "qualification cannot install"
  assert refreshCollectedLogical(chain, completion, default(SelectedLogicalParent), limits).error ==
      CollectedLogicalError.IdentityFailure
  let absent = refreshCollectedLogical(chain, completion, default(CurrentLogicalState), limits)
  assert absent.identityFailure.error == CurrentIdentityError.InvalidParent
  var short = limits
  short.identities.keys = ElementLimit(0)
  assert refreshCollectedLogical(chain, completion, source, short).identityFailure.error ==
      CurrentIdentityError.LimitExceeded
  short = limits
  short.requests.requests = ElementLimit(0)
  assert refreshCollectedLogical(chain, completion, source, short).requestFailure.error ==
      CurrentRequestKeyError.LimitExceeded
  short = limits
  short.reconstruction.checks = ElementLimit(0)
  assert refreshCollectedLogical(chain, completion, source, short).reconstructionFailure.error ==
      CurrentRefreshPlanError.LimitExceeded
  short = limits
  short.qualification.checks = ElementLimit(0)
  assert refreshCollectedLogical(chain, completion, source, short).qualificationFailure.error ==
      LogicalRefreshPlanError.LimitExceeded
  fail(1)
  assert refreshCollectedLogical(chain, completion, source, limits).error ==
      CollectedLogicalError.RequestFailure
  fail(0)
  for i in 0..<25: cycle(chain, completion, source)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(chain, completion, source)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("application_collected_logical", 1000, before, finalBytes)
  chain.installPrepared(completion.currentValue.value)
  assert refreshCollectedLogical(chain, completion, source, limits).error ==
      CollectedLogicalError.StaleUpdate
  # Cancellation keeps the lease through Done and grants no receipt payload after matching collection.
  let badId = receiveCurrent(input, chain, [255'u8], [], currentCandidateLimits())
  let cancelled = worker.submit(input, badId, chain).value
  worker.waitPreparationDone()
  assert worker.cancel(cancelled)
  let cancelledReceipt = worker.collect(cancelled)
  assert refreshCollectedLogical(chain, cancelledReceipt, source, limits).error ==
      CollectedLogicalError.Cancelled
  # A genuine current decoding failure retains its typed receiver cause after collection.
  let malformed = receiveCurrent(input, chain, [255'u8], [], currentCandidateLimits())
  let malformedTicket = worker.submit(input, malformed, chain).value
  worker.waitPreparationDone()
  let bad = refreshCollectedLogical(chain, worker.collect(malformedTicket), source, limits)
  assert bad.error == CollectedLogicalError.PreparationFailure
  assert bad.preparationFailure.error == CurrentBlockInputError.DecodeFailure
  # The shared worker's legacy alternative never grants current extraction or source matching.
  let old = legacy.begin(chain, ByteLimit(1), [], BlockInputLimits(blockBytes: ByteLimit(1)),
      ApplicationCandidateLimits(reporting: currentCandidateLimits().reporting)).value
  assert legacy.append(old, [255'u8], true) == BlockInputError.None
  let oldTicket = worker.submit(legacy, old, chain).value
  worker.waitPreparationDone()
  assert refreshCollectedLogical(chain, worker.collect(oldTicket), source, limits).error ==
      CollectedLogicalError.WrongOperation
  echo "application-collected-logical: ok"
try:
  main()
except:
  quit(2) # Fixture/thread exceptions fail independently of logical stage results.
