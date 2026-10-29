# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_round_runner_arc_release"}

## One current signed round composes selected state, yields and transfer budgets without guest replay or annulment gas refunds.
import std/[assertions, envvars, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, report_owned]
import ../../../src/codec/state/[outputs as state_outputs, layout as state_layout,
    trie as state_trie]
import ../../../src/pvm/[machine, step, gas]
import ../../../src/state/accumulation/current/round as accumulation_current_round
import ../../../src/state/accumulation/round as accumulation_round
import "../../../src/state/accumulation/block/guests" as accumulation_block_guests
import ../../../src/state/accumulation/guest_runner as accumulation_guest_runner
import ../../../src/state/accumulation/account/stage as accumulation_account_stage
import ../../../src/state/accumulation/provision/stage as accumulation_provision_stage
import ../../../src/state/accumulation/provisions as accumulation_provisions
import ../../../src/state/accumulation/global/stage as accumulation_global_stage
import ../../../src/state/accumulation/[coverage as accumulation_coverage,
    annulment as accumulation_annulment, outcome as accumulation_outcome,
    annulled_outputs as accumulation_annulled_outputs, transfers as accumulation_transfers,
    pending_transfers as accumulation_pending_transfers]
import ../../../src/state/store
import ../../support/[accumulation_execution_context, accumulation_current_guests_context,
  accumulation_current_round_context,
  pvm_accumulation_program, arc_evidence]
proc main() {.raises.} =
  ## Maintained fixtures authenticate source state/header/profile before the single current orchestration path executes.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve the exact report transport.
  let base = decodeOwnedReport(wire, 2).value
  var options = executionFixtureConfig()
  options.firstProgram = currentTransferProgram(99)
  let fixture = executionFixture(base, options)
  let before = fixture.state.snapshot.value
  let completed = runCurrentBlockAccumulationRound(fixture.round, currentRoundParameters(),
      currentRoundLimits())
  assert completed.error == CurrentAccumulationRoundError.None, $completed.error
  let plan = completed.value
  let guests = plan.currentRoundGuests.value
  let coverage = guests.guestCoverage.value.coverageInfo.value
  let pending = plan.currentRoundPending.value.pendingTransferInfo.value
  assert plan.currentRoundOutputs.value.annulmentOutputsInfo.value.outputs == 1, "selected yield retained"
  assert plan.currentRoundTransfers.value.transferCollectionInfo.value.transfers == 1, "selected transfer retained"
  assert pending.outgoing == 1 and pending.carried == 0 and uint64(pending.outgoingGas) == 3, "fresh transfer reservation retained"
  assert uint64(pending.gasUsed) == uint64(coverage.gasUsed), "pending usage equals original coverage gas"
  assert uint64(pending.budget) == uint64(pending.sourceBudget)-uint64(pending.gasUsed)+3, "recursive budget restores only fresh transfer gas"
  assert uint64(pending.reportBudget) == uint64(pending.sourceBudget)-uint64(pending.gasUsed), "report budget excludes reserved transfer gas"
  let accounts = prepareAccumulationAccountStage(guests, currentRoundLimits().accounts).value
  let provisions = prepareAccumulationProvisionStage(accounts, currentRoundLimits().provisions).value
  let globals = prepareAccumulationGlobalStage(provisions, currentRoundLimits().globals).value
  assert array[32, byte](globals.globalStageSnapshot.value.commitment.root) == array[32, byte](
      plan.currentRoundSnapshot.value.commitment.root)
  assert sameStateSnapshot(fixture.state.snapshot.value, before), "caller prior identity remains unchanged"
  var conflict = executionFixtureConfig()
  conflict.secondSupervisor = 42
  conflict.firstProgram = currentRoundServiceCode(@[registerImmediate(7, 99), registerImmediate(8,
      42), @[10'u8, 29], @[50'u8, 0]])
  conflict.secondProgram = currentTransferProgram(
      99) # The signed service42 has maximal minimum transfer gas; a real self-transfer is accepted.
  let canceledFixture = executionFixture(base, conflict)
  let canceled = runCurrentBlockAccumulationRound(canceledFixture.round, currentRoundParameters(),
      currentRoundLimits()).value
  let selection = canceled.currentRoundGuests.value.guestCoverage.value.coverageAnnulment.value
  assert selection.annulmentInfo.value.annulled == 1, "genuine supervisor/junior conflict"
  let junior = selection.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(1)).value
  assert junior.outcomeInfo.value.transfers == 1, "the original transfer really succeeded before annulment"
  let originalGas = canceled.currentRoundGuests.value.guestCoverage.value.coverageInfo.value.gasUsed
  let canceledPending = canceled.currentRoundPending.value.pendingTransferInfo.value
  assert uint64(originalGas) > 575, "annulled original gas is still consumed"
  assert canceled.currentRoundOutputs.value.annulmentOutputsInfo.value.outputs == 0, "annulled yield removed"
  assert canceledPending.outgoing == 0 and uint64(canceledPending.outgoingGas) == 0, "annulled outgoing transfer removed"
  assert uint64(canceledPending.gasUsed) == uint64(originalGas), "pending usage includes annulled original gas"
  assert uint64(canceledPending.budget) == uint64(canceledPending.sourceBudget)-uint64(originalGas), "annulment refunds neither original execution nor reserved transfer gas"
  for mode in 0..<7:
    var limits = currentRoundLimits()
    var expected = CurrentAccumulationRoundError.Uninitialized
    case mode
    of 0:
      limits.guests.services = ElementLimit(1)
      expected = CurrentAccumulationRoundError.GuestFailure
    of 1:
      limits.accounts.entries = ElementLimit(0)
      expected = CurrentAccumulationRoundError.AccountFailure
    of 2:
      limits.provisions.contexts = ElementLimit(1)
      expected = CurrentAccumulationRoundError.ProvisionFailure
    of 3:
      limits.globals.totalBytes = ByteLimit(0)
      expected = CurrentAccumulationRoundError.GlobalFailure
    of 4:
      limits.outputs.outcomes = ElementLimit(1)
      expected = CurrentAccumulationRoundError.OutputFailure
    of 5:
      limits.transfers.sources = ElementLimit(1)
      expected = CurrentAccumulationRoundError.TransferFailure
    else:
      limits.pending.sources = ElementLimit(1)
      expected = CurrentAccumulationRoundError.PendingFailure
    let failed = runCurrentBlockAccumulationRound(fixture.round, currentRoundParameters(), limits)
    assert failed.error == expected, $mode & ":" & $failed.error
    assert sameStateSnapshot(fixture.state.snapshot.value, before), "every late failure preserves the caller's complete state"
  var emptyOptions = executionFixtureConfig()
  emptyOptions.empty = true
  let emptyFixture = executionFixture(base, emptyOptions)
  let empty = runCurrentBlockAccumulationRound(emptyFixture.round, currentRoundParameters(),
      currentRoundLimits()).value
  assert empty.currentRoundGuests.value.guestCoverage.value.coverageInfo.value.services == 0, "genuine initialized empty current round"
  assert empty.currentRoundPending.value.pendingTransferInfo.value.transfers == 0, "no fabricated pending execution"
  let refused = runCurrentBlockAccumulationRound(default(BlockAccumulationRound),
      currentRoundParameters(), currentRoundLimits())
  assert refused.error == CurrentAccumulationRoundError.GuestFailure, "current round check at authored line124"
  assert refused.guestFailure.error == BlockGuestError.InvalidRound, "current round check at authored line125"
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = runCurrentBlockAccumulationRound(fixture.round, currentRoundParameters(),
        currentRoundLimits()).value
    assert local.currentRoundPending.value.pendingTransferInfo.value.outgoing ==
        1 # Ready guests execute once within each fresh complete run; all private owners release.
  let after = getOccupiedMem()
  assert occupied == after, "current complete parallel round releases"
  recordArcRelease("pvm_current_round_runner", 1000, occupied, after)
  echo "PVM current round runner passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Native/admission/setup errors must fail rather than publish an empty current round.
except:
  quit(2)
