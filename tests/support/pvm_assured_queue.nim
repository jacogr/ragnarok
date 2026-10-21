# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual assured successor sources and original-parameter-bound admission/queue policies for subsequent accumulation.

import ../../src/state/[assured_queue, computed_assurances, report_admission, report_policy,
    report_anchors, guarantors, block_transition]
import ../../src/chain/parameters
import ../../src/codec/[bounded, assurances]
import ./[pvm_computed_assurances, report_admission_context, accumulation_execution_context]

proc assuredQueueFixture*(votes = 7): AssuredComputedReports =
  ## Sign the real next block against its published computed parent; no ready row is inserted for these reports.
  let prior = assurancePrior()
  prepareComputedAssurances(prior, assuranceCandidate(prior, votes = votes),
      computedAssuranceConfig()).value
proc assuredQueueConfig*(source: AssuredComputedReports): AssuredQueueConfig =
  ## Match original semantic controls and real frame domains while retaining independent existing byte/work ceilings.
  let params = source.computedAssuranceParameters.value
  let frame = source.computedAssuranceStage.value.blockTransitionProfile
  result = AssuredQueueConfig(admission: config(), queue: executionQueueConfig())
  result.admission.credentials.assignments.roster.cores = frame.cores
  result.admission.credentials.assignments.roster.validators = ElementLimit(uint64(
      frame.validators))
  result.admission.credentials.assignments.epochSlots = frame.epochSlots
  result.admission.credentials.assignments.rotationSlots = GuarantorRotationSlots(params.get(rotationPeriod))
  result.admission.policy.pools.cores = frame.cores
  result.admission.policy.reportGas = ReportGasLimit(params.get(maxAccumulateGas))
  result.admission.anchors.history.cores = frame.cores
  result.admission.anchors.lookupAge = LookupAge(params.get(maxLookupAnchorAge))
  result.admission.packages.availability.guarantee.cores = frame.cores
  result.admission.packages.availability.guarantee.validators = frame.validators
  result.admission.packages.queues.cores = frame.cores
  result.admission.packages.queues.epochSlots = frame.epochSlots
  result.admission.ancestors.header.cores = frame.cores
  result.admission.ancestors.header.authorValidators = frame.validators
  result.admission.ancestors.header.epochSlots = frame.epochSlots
  result.queue.queues.cores = frame.cores
  result.queue.queues.epochSlots = frame.epochSlots
