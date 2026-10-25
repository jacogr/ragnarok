# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared three-core/nine-validator reporting budgets and exact nested scenario failures; no executable entry point.
import ../../src/app/[chain, candidate]
import ../../src/codec/bounded
import ../../src/state/[accumulation_current_completion, accumulation_current_driver,
    accumulation_current_round, accumulation_block_guests, accumulation_guest_runner,
    block_transition, block_admission, disputes]
import ./[current_stf_population_context, current_stf_reporting_context, current_stf_guest_limits]

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
  # Reuse the qualified literal-guest fetch/blob policy, explicitly admitting four same-service report operands.
  let execution = currentStfGuestLimits()
  result.completion.execution.initial.guests.fetch = execution.completion.execution.initial.guests.fetch
  result.completion.execution.initial.guests.fetch.items = ElementLimit(4)
  result.completion.execution.execution.round.guests.fetch = result.completion.execution.initial.guests.fetch
  result.completion.composition.statistics.operands = ElementLimit(5)
  result.completion.composition.finalization.history.reports = ElementLimit(5)
  result.completion.composition.finalization.history.queues.perSlot = ElementLimit(5)
  result.completion.composition.finalization.history.queues.totalItems = ElementLimit(13)
  result.completion.composition.validators.preimageBytes = ByteLimit(512)
  result.completion.composition.activity.preimages.perBlob = ByteLimit(512)
  result.completion.composition.activity.preimages.totalBlobBytes = ByteLimit(512)
  result.completion.composition.preimages.bytes = ByteLimit(512)
  # Original/output three-core queues plus nine-member staging exceed the earlier20KB aggregate.
  result.completion.execution.initial.globals.totalBytes = ByteLimit(22000)
  result.completion.execution.execution.round.globals.totalBytes = ByteLimit(22000)

proc populationReason*(outcome: CurrentCandidateResult): string =
  ## Distinguish a failed completion stage from an admission refusal during scoped corpus diagnosis.
  if outcome.error == CurrentCandidateError.CompletionFailure:
    let completed = outcome.completionFailure
    result = "completion/" & $completed.error
    if completed.error == CurrentAccumulationCompletionError.SequenceFailure:
      let sequence = completed.sequenceFailure
      result.add("/" & $sequence.error)
      if sequence.error == CurrentSequenceDriverError.InitialFailure:
        let initial = sequence.initialFailure
        result.add("/" & $initial.error)
        if initial.error == CurrentAccumulationRoundError.GuestFailure:
          let blockGuests = initial.guestFailure
          result.add("/" & $blockGuests.error)
          if blockGuests.error == BlockGuestError.GuestFailure:
            let guest = blockGuests.guestFailure
            result.add("/" & $guest.error)
            if guest.error == AccumulationGuestError.DispatchFailure:
              result.add("/" & $guest.dispatchFailure.error)
    return
  if outcome.error == CurrentCandidateError.PrefixFailure:
    let prefix = outcome.prefixFailure
    if prefix.error == ApplicationCandidateError.BlockFailure and
        prefix.blockFailure.error == BlockTransitionError.AdmissionFailure:
      return "admission/" & $prefix.blockFailure.admissionError
    if prefix.error == ApplicationCandidateError.BlockFailure and
        prefix.blockFailure.error == BlockTransitionError.DisputesFailure:
      return "dispute/" & $prefix.blockFailure.disputesError
  reportingReason(outcome)

