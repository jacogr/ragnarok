# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual assured successor sources and original-parameter-bound admission/queue policies for subsequent accumulation.

import ../../src/state/assured_queue as state_assured_queue
import ../../src/state/computed_assurances as state_computed_assurances
import ../../src/state/report_admission as state_report_admission
import ../../src/state/report_policy as state_report_policy
import ../../src/state/report_anchors as state_report_anchors
import ../../src/state/guarantors as state_guarantors
import ../../src/state/block_transition as state_block_transition
import ../../src/chain/parameters as chain_parameters
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/assurances as codec_assurances
import ./pvm_computed_assurances
import ./state_report_admission_context
import ./state_accumulation_execution_context

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
