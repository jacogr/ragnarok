# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine composed computed state and its original parent for publication and later chain-view witnesses.

import ../../src/state/[computed_composition, computed_finalization, accumulation_finalization, store]
import ./pvm_computed_composition

proc statePublicationFixture*(): ComposedComputedState =
  ## Complete genuine computation, stopped accumulation and maintained composition before testing publication.
  composeComputedState(compositionFixture(), computedCompositionLimits()).value
proc statePublicationParent*(source: ComposedComputedState): StateStoreSnapshot =
  ## Derive the exact original parent only through retained computed finalization authority.
  source.computedCompositionSource.value.computedFinalizationPlan.value.finalAccumulationParent.value
