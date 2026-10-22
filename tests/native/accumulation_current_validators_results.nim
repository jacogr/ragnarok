# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused current validator owners expose no observations, projection, source or inactive nested cause.
import std/cmdline
import ../../src/state/[accumulation_current_validators, accumulation_validators,
    accumulation_current_recent]
let owner = default(CurrentAccumulationValidatorsResult[PreparedCurrentAccumulationValidators])
let validators = default(PreparedCurrentAccumulationValidators)
let refused = prepareCurrentAccumulationValidators(default(PreparedCurrentAccumulationRecent),
    default(AccumulationValidatorsConfig))
case paramStr(1)
of "refused": discard refused.value # No successful current prefix after refusal.
of "source": discard validators.currentValidatorsSource.value # No synthetic recent provenance.
of "observations": discard validators.currentValidatorsObservations.value # No caller clock or fabricated body counters.
of "projection": discard validators.currentValidatorsProjection.value # No default validator tuples.
of "state": discard validators.currentValidatorsState.value # No fake complete map.
of "roster-reason": discard refused.rosterError # Require real selected roster failure.
of "activity-reason": discard refused.activityError # Require real selected C13 failure.
of "projection-reason": discard refused.projectionError # Require real selected pure projection failure.
else: discard owner.value # Default tagged result remains uninitialized.
