# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared three-core/nine-validator reporting budgets and exact nested scenario failures; no executable entry point.
import ../../src/app/[chain, candidate]
import ../../src/codec/bounded
import ../../src/state/[accumulation_current_completion, block_transition, disputes]
import ./[current_stf_population_context, current_stf_reporting_context]

proc populationReportingLimits*(): CurrentCandidateLimits =
  ## Nine prior/current assurers, three active cores and key-identity comparisons have explicit finite ceilings.
  result = populationLimits()
  result.reporting.reports.credentials.reporters = ElementLimit(9)
  result.reporting.availability.availableReports = ElementLimit(3)
  result.reporting.reports.anchors.history.perBlock = ElementLimit(3)
  result.reporting.reports.anchors.history.totalPackages = ElementLimit(24)
  result.completion.composition.recent.history.perBlock = ElementLimit(3)
  result.completion.composition.recent.history.totalPackages = ElementLimit(24)
  result.completion.composition.activity.incoming = ElementLimit(3)
  result.completion.composition.activity.digests = ElementLimit(3)
  result.completion.composition.authorization.guarantees = ElementLimit(3)
  result.completion.composition.validators.projection.assurances = ElementLimit(9)
  result.completion.composition.validators.projection.reporters = ElementLimit(9)
  result.completion.composition.validators.projection.comparisons = ElementLimit(81)
  result.completion.composition.activity.available = ElementLimit(3)
  result.completion.composition.activity.assurances = ElementLimit(9)

proc populationReason*(outcome: CurrentCandidateResult): string =
  ## Distinguish a failed completion stage from an admission refusal during scoped corpus diagnosis.
  if outcome.error == CurrentCandidateError.CompletionFailure:
    return "completion/" & $outcome.completionFailure.error
  if outcome.error == CurrentCandidateError.PrefixFailure:
    let prefix = outcome.prefixFailure
    if prefix.error == ApplicationCandidateError.BlockFailure and
        prefix.blockFailure.error == BlockTransitionError.DisputesFailure:
      return "dispute/" & $prefix.blockFailure.disputesError
  reportingReason(outcome)

