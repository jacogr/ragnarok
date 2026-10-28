# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_reusable_selected_phases_arc_release"}

## Explicit-input current coverage reuses complete selected algorithms without gaining authenticated initial-block ownership.
import std/assertions
import std/syncio
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/header as codec_header
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/state/accumulation_guest_runner as state_accumulation_guest_runner
import ../../../src/state/accumulation_coverage as state_accumulation_coverage
import ../../../src/state/accumulation_account_phase as state_accumulation_account_phase
import ../../../src/state/accumulation_provision_phase as state_accumulation_provision_phase
import ../../../src/state/accumulation_global_phase as state_accumulation_global_phase
import ../../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../../src/state/store as state_store
import ../../support/state_accumulation_batch_context
import ../../support/state_accumulation_current_guests_context
import ../../support/pvm_accumulation_program
import ../../support/testing_arc_evidence
proc provisions(): AccumulationProvisionUnionLimits =
  ## Two genuine original contexts are traversed even when both provide sets are empty.
  AccumulationProvisionUnionLimits(contexts: ElementLimit(2),
    values: PreimageLimits(items: ElementLimit(0), perBlob: ByteLimit(0), totalBlobBytes: ByteLimit(
        0)), encodedBytes: ByteLimit(8))
proc coverage(): PreparedAccumulationCoverage =
  ## Explicit frame/state choices are genuine guest inputs, but intentionally carry no block admission certificate.
  let envelope = guestEnvelope([@[50'u8, 0]])
  let fixture = batchFixture(incoming = false, firstEnvelope = envelope,
      secondEnvelope = envelope) # Explicit identity guests perform no provide work under the zero provision policy.
  let executed = runAccumulationGuests(fixture.inputs, fixture.state.snapshot.value, HeaderSlot(128),
    default(StateEntropyWord), currentGuestParameters(), currentGuestLimits())
  assert executed.error == AccumulationGuestError.None, $executed.error
  executed.value
let source = coverage()
let accounts = prepareAccumulationAccountPhase(source, currentAccountStageLimits())
assert accounts.error == AccumulationAccountPhaseError.None, $accounts.error
assert accounts.value.accountPhaseInfo.value.priorAccounts == 2
let provided = prepareAccumulationProvisionPhase(accounts.value, provisions())
assert provided.error == AccumulationProvisionPhaseError.None, $provided.error
let globals = prepareAccumulationGlobalPhase(provided.value, currentGlobalStageLimits())
assert globals.error == AccumulationGlobalPhaseError.None, $globals.error
assert globals.value.globalPhaseInfo.value.cores == 2
assert globals.value.globalPhaseProvisions.value.provisionPhaseAccounts.value.accountPhaseInfo.value.priorAccounts == 2
assert array[32, byte](globals.value.globalPhaseSnapshot.value.commitment.root) ==
  array[32, byte](accounts.value.accountPhaseSnapshot.value.commitment.root), "unchanged explicit phases preserve the complete serialized root"
let refused = prepareAccumulationAccountPhase(default(PreparedAccumulationCoverage),
    currentAccountStageLimits())
assert refused.error == AccumulationAccountPhaseError.InvalidSource
assert default(PreparedAccumulationAccountPhase).accountPhaseCoverage.error ==
    AccumulationAccountPhaseError.Uninitialized
let badProvision = prepareAccumulationProvisionPhase(default(PreparedAccumulationAccountPhase),
    provisions())
assert badProvision.error == AccumulationProvisionPhaseError.InvalidSource
let badGlobal = prepareAccumulationGlobalPhase(default(PreparedAccumulationProvisionPhase),
    currentGlobalStageLimits())
assert badGlobal.error == AccumulationGlobalPhaseError.InvalidSource
let occupied = getOccupiedMem()
for iteration in 0..<1000:
  let localAccounts = prepareAccumulationAccountPhase(source, currentAccountStageLimits()).value
  let localProvided = prepareAccumulationProvisionPhase(localAccounts, provisions()).value
  let localGlobals = prepareAccumulationGlobalPhase(localProvided, currentGlobalStageLimits()).value
  assert localGlobals.globalPhaseInfo.value.cores ==
      2 # Explicit coverage owners and all private phase forks release without admission wrappers.
let after = getOccupiedMem()
assert occupied == after, "reusable selected phases release"
recordArcRelease("pvm_reusable_selected_phases", 1000, occupied, after)
echo "PVM reusable selected phases passed"
echo "ARC_RELEASE cycles=1000 unchanged"
