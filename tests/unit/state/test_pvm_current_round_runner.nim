# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_round_runner_arc_release"}

## One current signed round composes selected state, yields and transfer budgets without guest replay or annulment gas refunds.
import std/[assertions, envvars, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, report_owned, state_outputs, state_layout, state_trie]
import ../../../src/pvm/[machine, step, gas]
import ../../../src/state/[accumulation_current_round, accumulation_round,
  accumulation_block_guests,
  accumulation_guest_runner, accumulation_account_stage, accumulation_provision_stage,
  accumulation_provisions, accumulation_global_stage, accumulation_coverage, accumulation_annulment,
  accumulation_outcome,
  accumulation_annulled_outputs, accumulation_transfers, accumulation_pending_transfers, store]
import ../../support/[accumulation_execution_context, accumulation_current_guests_context,
  pvm_accumulation_program, arc_evidence]
proc policy(): CurrentAccumulationRoundLimits =
  ## Independent phase policies make every actual parent refusal observable without weakening later completeness.
  var guests = currentGuestLimits()
  guests.steps = ExecutionStepLimit(200)
  guests.calls = HostCallLimit(32)
  guests.copyBytes = MemoryByteLimit(128)
  guests.transfers = ElementLimit(2)
  guests.modifiedAccounts = ElementLimit(8)
  guests.accountWriteFacts = ElementLimit(8)
  CurrentAccumulationRoundLimits(guests: guests, accounts: currentAccountStageLimits(),
    provisions: AccumulationProvisionUnionLimits(contexts: ElementLimit(2),
      values: PreimageLimits(items: ElementLimit(0), perBlob: ByteLimit(0),
          totalBlobBytes: ByteLimit(0)), encodedBytes: ByteLimit(8)),
    globals: currentGlobalStageLimits(),
    outputs: AnnulmentOutputLimits(outcomes: ElementLimit(2), log: OutputLogConfig(
        items: ElementLimit(2), maxBytes: ByteLimit(100))),
    transfers: AccumulationTransferCollectionLimits(sources: ElementLimit(2),
        transfers: ElementLimit(2), memoBytes: ByteLimit(256)),
    pending: PendingTransferLimits(sources: ElementLimit(2), transfers: ElementLimit(2),
        memoBytes: ByteLimit(256)))
proc parameters(): Parameters =
  ## Match the genuine tiny chain and current fixed128-byte transfer memo independently of local copy limits.
  var wire = encodeParameters(currentGuestParameters())
  for index in 110..<114: wire[index] = 0 # Entire Appendix B memo extent, not a truncated override.
  wire[110] = 128
  decodeParameters(wire).value
proc code(instructions: seq[seq[byte]]): seq[byte] =
  ## Real deferred transfer and yield instructions share one canonical service preimage/envelope.
  result = @[0'u8]
  for octet in guestEnvelope(instructions, writable = newSeq[byte](128)): result.add(octet)
proc transferCode(destination: uint64): seq[byte] =
  ## A genuine nonzero memo pointer selects deferred transfer even with zero token value.
  code(@[registerImmediate(7, high(uint64)), registerImmediate(8, destination), registerImmediate(9, 0),
    registerImmediate(10, 0), registerImmediate(11, 3), registerImmediate(12, 196608), @[10'u8, 22],
    registerImmediate(7, 65536), @[10'u8, 27], @[50'u8, 0]])
proc main() {.raises.} =
  ## Maintained fixtures authenticate source state/header/profile before the single current orchestration path executes.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve the exact report transport.
  let base = decodeOwnedReport(wire, 2).value
  var options = executionFixtureConfig()
  options.firstProgram = transferCode(99)
  let fixture = executionFixture(base, options)
  let before = fixture.state.snapshot.value
  let completed = runCurrentBlockAccumulationRound(fixture.round, parameters(), policy())
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
  let accounts = prepareAccumulationAccountStage(guests, policy().accounts).value
  let provisions = prepareAccumulationProvisionStage(accounts, policy().provisions).value
  let globals = prepareAccumulationGlobalStage(provisions, policy().globals).value
  assert array[32, byte](globals.globalStageSnapshot.value.commitment.root) == array[32, byte](
      plan.currentRoundSnapshot.value.commitment.root)
  assert sameStateSnapshot(fixture.state.snapshot.value, before), "caller prior identity remains unchanged"
  var conflict = executionFixtureConfig()
  conflict.secondSupervisor = 42
  conflict.firstProgram = code(@[registerImmediate(7, 99), registerImmediate(8, 42), @[10'u8, 29],
      @[50'u8, 0]])
  conflict.secondProgram = transferCode(99) # The signed service42 has maximal minimum transfer gas; a real self-transfer is accepted.
  let canceledFixture = executionFixture(base, conflict)
  let canceled = runCurrentBlockAccumulationRound(canceledFixture.round, parameters(), policy()).value
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
    var limits = policy()
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
    let failed = runCurrentBlockAccumulationRound(fixture.round, parameters(), limits)
    assert failed.error == expected, $mode & ":" & $failed.error
    assert sameStateSnapshot(fixture.state.snapshot.value, before), "every late failure preserves the caller's complete state"
  var emptyOptions = executionFixtureConfig()
  emptyOptions.empty = true
  let emptyFixture = executionFixture(base, emptyOptions)
  let empty = runCurrentBlockAccumulationRound(emptyFixture.round, parameters(), policy()).value
  assert empty.currentRoundGuests.value.guestCoverage.value.coverageInfo.value.services == 0, "genuine initialized empty current round"
  assert empty.currentRoundPending.value.pendingTransferInfo.value.transfers == 0, "no fabricated pending execution"
  let refused = runCurrentBlockAccumulationRound(default(BlockAccumulationRound), parameters(),
      policy())
  assert refused.error == CurrentAccumulationRoundError.GuestFailure, "current round check at authored line124"
  assert refused.guestFailure.error == BlockGuestError.InvalidRound, "current round check at authored line125"
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = runCurrentBlockAccumulationRound(fixture.round, parameters(), policy()).value
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
