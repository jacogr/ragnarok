# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual assured PVM completion with bounded stopped-history and whole successor composition policies.

import ../../src/codec/bounded
import ../../src/state/[assured_execution, assured_composition]
import ./[pvm_assured_execution, pvm_computed_finalization, pvm_computed_composition]

proc assuredCompositionFixture*(votes = 7): ExecutedAssuredAccumulation =
  ## Execute the actual previously computed reports only after genuine next-block assurances and admission.
  let source = assuredExecutionFixture(votes)
  executeAssuredAccumulation(source, assuredExecutionConfig(source)).value
proc assuredCompositionConfig*(): AssuredCompositionConfig =
  ## Preserve original tiny policies; no continuation guest is needed after the complete two-report prefix.
  let final = computedFinalizationConfig()
  result = AssuredCompositionConfig(driver: final.driver, outputs: final.outputs,
    composition: computedCompositionLimits())
  result.composition.validators.projection.rows = ElementLimit(
      15) # Nine current and six previous validator rows are retained together.
  result.composition.validators.projection.assurances = ElementLimit(
      7) # Seven genuine signatures establish availability in this fixture.
