# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict computed-assurance result and report-view guards retain a real authenticated successor as their positive control.

import std/[assertions, cmdline]
import ../../src/state/computed/[assurances as computed_assurances, chain as computed_chain]
import "../../src/state/block/transition" as block_transition
import ../../src/codec/[bounded, assurances]
import ../support/pvm_computed_assurances

proc expect[T](outcome: ComputedAssuranceResult[T], reason: ComputedAssuranceError) =
  ## Confirm exact selected alternatives without statically folding deliberate runtime contract misuse.
  assert outcome.error == reason, "computed assurance runtime control"
let prior = assurancePrior()
let candidate = assuranceCandidate(prior)
let config = computedAssuranceConfig()
let done = prepareComputedAssurances(prior, candidate, config)
expect(done, ComputedAssuranceError.None)
assert done.value.computedAssuranceInfo.value.computed == 2
let invalid = prepareComputedAssurances(default(AdvancedComputedChain), candidate, config)
expect(invalid, ComputedAssuranceError.InvalidSource)
var changed = config
changed.admission.frame.cores = CoreCount(2)
let profile = prepareComputedAssurances(prior, candidate, changed)
expect(profile, ComputedAssuranceError.ProfileMismatch)
changed = config
changed.reports = ElementLimit(1)
let count = prepareComputedAssurances(prior, candidate, changed)
expect(count, ComputedAssuranceError.LimitExceeded)
changed = config
changed.reportBytes = ByteLimit(0)
let bytes = prepareComputedAssurances(prior, candidate, changed)
expect(bytes, ComputedAssuranceError.LimitExceeded)
let transition = prepareComputedAssurances(prior, assuranceCandidate(prior, badSignature = true), config)
expect(transition, ComputedAssuranceError.TransitionFailure)
assert transition.transitionFailure.error == BlockTransitionError.AvailabilityFailure
let empty = prepareComputedAssurances(prior, assuranceCandidate(prior, votes = 6), config)
expect(empty, ComputedAssuranceError.None)
assert empty.value.computedAssuranceInfo.value.computed == 0
let missing = default(ComputedAssuranceResult[AssuredComputedReports])
case paramStr(1)
of "default": discard missing.value # A refused/default constructor owns no authenticated computed availability.
of "source": discard invalid.value # A refused/default constructor owns no authenticated computed availability.
of "profile": discard profile.value # A refused/default constructor owns no authenticated computed availability.
of "count": discard count.value # A refused/default constructor owns no authenticated computed availability.
of "bytes": discard bytes.value # A refused/default constructor owns no authenticated computed availability.
of "transition": discard transition.value # A refused/default constructor owns no authenticated computed availability.
of "owner": discard default(AssuredComputedReports).computedAssuranceSource.value # An uninitialized owner has no usable selected view.
of "stage": discard default(AssuredComputedReports).computedAssuranceStage.value # An uninitialized owner has no usable selected view.
of "parameters": discard default(AssuredComputedReports).computedAssuranceParameters.value # An uninitialized owner has no usable selected view.
of "info": discard default(AssuredComputedReports).computedAssuranceInfo.value # An uninitialized owner has no usable selected view.
of "report": discard default(AssuredComputedReports).computedAssuredReportAt(ComputedAvailableIndex(
    0)).value # An uninitialized owner has no usable selected view.
of "index": discard done.value.computedAssuredReportAt(ComputedAvailableIndex(high(
    uint64))).value # Full-width invalid report ordinal carries no output.
of "quorum": discard empty.value.computedAssuredReportAt(ComputedAvailableIndex(
    0)).value # Insufficient genuine votes expose no computed report.
of "stateError-default": discard missing.stateError # Only the selected precise child cause is readable.
of "stateError-success": discard done.stateError # Only the selected precise child cause is readable.
of "stateError-source": discard invalid.stateError # Only the selected precise child cause is readable.
of "stateError-other": discard transition.stateError # Only the selected precise child cause is readable.
of "transitionFailure-default": discard missing.transitionFailure # Only the selected precise child cause is readable.
of "transitionFailure-success": discard done.transitionFailure # Only the selected precise child cause is readable.
of "transitionFailure-source": discard invalid.transitionFailure # Only the selected precise child cause is readable.
of "transitionFailure-other": discard profile.transitionFailure # Only the selected precise child cause is readable.
of "reportError-default": discard missing.reportError # Only the selected precise child cause is readable.
of "reportError-success": discard done.reportError # Only the selected precise child cause is readable.
of "reportError-source": discard invalid.reportError # Only the selected precise child cause is readable.
of "reportError-other": discard transition.reportError # Only the selected precise child cause is readable.
else: discard invalid.value # Unknown modes never bypass deliberate contract enforcement.
