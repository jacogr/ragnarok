# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized state-binding guards include genuine independent sealed-parent and map-identity controls.

import std/assertions
import std/cmdline
import ../../src/state/computed_state as state_computed_state
import ../../src/state/computed_links as state_computed_links
import ../../src/state/block_admission as state_block_admission
import ../../src/state/store as state_store
import ../support/pvm_computed_state

proc check[T](outcome: ComputedStateResult[T], reason: ComputedStateError) =
  ## Confirm selected alternatives before deliberate unsuccessful extraction.
  assert outcome.error == reason, "computed state guard control"
let fixture = stateFixture()
let original = fixture.state.snapshot.value
let done = bindComputedState(fixture.source, fixture.admission)
check(done, ComputedStateError.None)
assert sameStateSnapshot(done.value.computedStateSnapshot.value, original), "genuine exact map control"
let clone = clonedState(original)
let foreign = stateAdmission(clone.snapshot.value)
assert foreign.error == BlockAdmissionError.None, "genuine independent admission control"
let missing = default(ComputedStateResult[StateBoundComputedReport])
let source = bindComputedState(default(ComputedReportLinks), fixture.admission)
check(source, ComputedStateError.InvalidSource)
let admission = bindComputedState(fixture.source, default(BlockAdmissionResult))
check(admission, ComputedStateError.InvalidAdmission)
let state = bindComputedState(fixture.source, foreign)
check(state, ComputedStateError.StateMismatch)
case paramStr(1)
of "default": discard missing.value # Defaults contain no bound report.
of "source": discard source.value # No original computed provenance.
of "admission": discard admission.value # No complete-map block binding.
of "state": discard state.value # Equal roots cannot replace exact original snapshot identity.
of "owner": discard default(StateBoundComputedReport).computedStateSource.value # No original computation in defaults.
of "block": discard default(StateBoundComputedReport).computedStateAdmission.value # No invented block binding.
else: discard default(StateBoundComputedReport).computedStateSnapshot.value # No invented empty complete state.
