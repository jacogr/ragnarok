# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual managed preparation and proof leases reject both logical source alternatives before canonical access.
import std/[assertions, cmdline, syncio, strutils, monotimes, times]
import ../../src/app/[services, current_logical, preparation_worker, current_block_input, proof_worker]
import ../../src/state/[parent_logical, current_logical, proof_plan]
import ../../src/codec/[bounded, report_owned, state_layout]
import ../../src/chain/[provider, genesis]
import ../support/[current_repeated_logical_context, collected_logical_context,
    collected_logical_services_context, accumulation_current_candidate_context, current_logical_proof_context]
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Scalar-only native deadline polling cannot touch a leased canonical graph.
proc main() {.raises.} =
  ## Every probe starts real managed native work; setup or ordinary exceptions never count as contract failure.
  let mode = paramStr(1)
  let raw = readFile("tests/fixtures/state-report.bin")
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = repeatedLogicalFixture(decodeOwnedReport(bytes, 2).value)
  var owner = default(Services)
  var input = default(CurrentBlockInput)
  let source = startLogicalServices(owner, fixture, "build/application-logical-guard-chain.json")
  defer: owner.close() # Positive joined cleanup retires either native borrower before source/input aliases.
  if mode == "control":
    let receipt = default(PreparationCompletion)
    assert owner.refreshCollectedLogical(receipt, source, collectedLogicalTestLimits()).error ==
        CollectedLogicalError.NoCompletion
    return
  if mode.startsWith("preparation"):
    let ticket = beginManagedCurrent(owner, input, [255'u8], [], currentCandidateLimits())
    owner.waitManagedPreparation()
    assert owner.cancelPreparation(ticket)
    assert owner.preparationActive # Done plus cancellation retains the actual graph lease.
  else:
    let selected = owner.chainView.bestBlock.value.blockHash
    let plan = captureStateProofPlan([chapterKey(StateChapter(11))], ElementLimit(1)).value
    let ticket = owner.beginStateProof(selected, plan, logicalProofLimits()).value
    let start = getMonoTime()
    while owner.stateProofPhase != ProofWorkerPhase.Done:
      assert (getMonoTime()-start).inSeconds < 20
      discard pauseMicros(1000)
    assert owner.cancelStateProof(ticket)
    assert owner.stateProofActive # Proof Done plus cancellation keeps the same canonical exclusion.
  let receipt = default(PreparationCompletion)
  if mode.endsWith("selected"):
    let empty = default(SelectedLogicalParent)
    discard owner.refreshCollectedLogical(receipt, empty, collectedLogicalTestLimits())
  else:
    let empty = default(CurrentLogicalState)
    discard owner.refreshCollectedLogical(receipt, empty, collectedLogicalTestLimits())
try:
  main()
except:
  quit(2) # Only exact AssertionDefect exits satisfy the strict negative verdicts.
