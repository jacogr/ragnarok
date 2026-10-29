# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict computed full-state composition/refusal probes retain genuine composed pending guarantees as a positive control.

import std/[assertions, cmdline]
import ../../src/state/computed/[composition as computed_composition,
    finalization as computed_finalization]
import ../../src/state/accumulation/[completion as accumulation_completion,
    consensus as accumulation_consensus]
import ../../src/codec/bounded
import ../support/pvm_computed_composition

proc expect[T](outcome: ComputedCompositionResult[T], reason: ComputedCompositionError) =
  ## Confirm exact alternatives before deliberate missing value or unrelated child-cause extraction.
  assert outcome.error == reason, "computed composition runtime control"
let source = compositionFixture()
let limits = computedCompositionLimits()
let done = composeComputedState(source, limits)
expect(done, ComputedCompositionError.None)
assert done.value.computedCompositionPlan.value.accumulationConsensusInfo.value.chapters == 7
let invalid = composeComputedState(default(FinalizedComputedAccumulation), limits)
expect(invalid, ComputedCompositionError.InvalidSource)
var changed = limits
changed.history.reports = ElementLimit(0)
let early = composeComputedState(source, changed)
expect(early, ComputedCompositionError.CompositionFailure)
assert early.compositionFailure.error == AccumulationCompletionError.HistoryFailure
changed = limits
changed.consensus.chapterBytes = ByteLimit(0)
let late = composeComputedState(source, changed)
expect(late, ComputedCompositionError.CompositionFailure)
assert late.compositionFailure.error == AccumulationCompletionError.ConsensusFailure
let missing = default(ComputedCompositionResult[ComposedComputedState])
case paramStr(1)
of "default": discard missing.value # Default owns no composed map.
of "source": discard invalid.value # Loose/default finalization has no authority.
of "early": discard early.value # Early phase refusal exposes no state prefix.
of "late": discard late.value # Late phase refusal also exposes no earlier successful map.
of "owner": discard default(ComposedComputedState).computedCompositionSource.value # No original computed work.
of "plan": discard default(ComposedComputedState).computedCompositionPlan.value # No real consensus composition.
of "reason-default": discard missing.compositionFailure # Default contains no failed phase.
of "reason-success": discard done.compositionFailure # Success contains no unrelated refusal.
else: discard invalid.compositionFailure # Invalid-source refusal contains no child success/failure payload.
