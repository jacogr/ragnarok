# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original-source admission policies retain semantic parameters while independently bounding resources.

import std/assertions
import ../../src/state/[computed_inclusion, computed_batch, computed_envelope, computed_credentials,
  computed_guarantors, computed_roster, computed_transition, computed_profile, report_admission,
  report_policy, report_anchors, guarantors]
import ../../src/chain/parameters
import ../../src/codec/[bounded, assurances, report_owned, owned]
import ./[pvm_computed_inclusion, report_admission_context]

proc computedAdmissionConfig*(source: IncludedComputedGuarantees): ReportAdmissionConfig =
  ## Match all original protocol knobs while keeping existing finite chapter/ancestor byte policies.
  let batch = source.computedInclusionSource.value
  let first = batch.computedBatchSourceAt(ComputedBatchIndex(0)).value
  let original = first.computedEnvelopeSource.value.computedCredentialSource.value.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileContext.value
  result = config()
  result.credentials.assignments.roster.cores = CoreCount(3)
  result.credentials.assignments.roster.validators = ElementLimit(9)
  result.credentials.assignments.rotationSlots = GuarantorRotationSlots(original.parameters.get(rotationPeriod))
  result.policy.pools.cores = CoreCount(3)
  result.policy.reportGas = ReportGasLimit(original.parameters.get(maxAccumulateGas))
  result.anchors.history.cores = CoreCount(3)
  result.anchors.lookupAge = LookupAge(original.parameters.get(maxLookupAnchorAge))
  result.packages.availability.guarantee.cores = CoreCount(3)
  result.packages.availability.guarantee.validators = ValidatorCount(9)
  result.packages.queues.cores = CoreCount(3)
  result.ancestors.header.cores = CoreCount(3)
  result.ancestors.header.authorValidators = ValidatorCount(9)
proc admissionFixture*(distinctPackages = true, withReady = false,
    withRound = false, withExecution = false, invalidEntry = false,
        withComposition = false): IncludedComputedGuarantees =
  ## Two distinct original packages are executed before signing; optional duplicates exercise actual package refusal.
  let batch = inclusionFixture(distinctPackages = distinctPackages, withReady = withReady,
      withRound = withRound, withExecution = withExecution, invalidEntry = invalidEntry,
      withComposition = withComposition)
  let first = batch.computedBatchSourceAt(ComputedBatchIndex(
      0)).value.computedEnvelopeGuarantee.value.report
  let second = batch.computedBatchSourceAt(ComputedBatchIndex(
      1)).value.computedEnvelopeGuarantee.value.report
  let left = ownedReportInfo(first).value.header.packageHash.bytes
  let right = ownedReportInfo(second).value.header.packageHash.bytes
  assert (left != right) == distinctPackages, "fixture authored package identities before execution"
  bindComputedInclusion(batch, ByteLimit(100000)).value
