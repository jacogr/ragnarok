# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Refused/default availability results and opaque owners cannot expose reports, updates or
## nonselected causes.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/cmdline
import std/syncio
import ../../src/state/availability as state_availability
import ../../src/state/block_transition as state_block_transition
import ../../src/state/store as state_store
import ../../src/codec/state_availability as codec_state_availability
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/codec/assurances as codec_assurances
import ../../src/crypto/assurance_context as crypto_assurance_context
var state = default(StateStore)
case paramStr(1)
of "plan-default", "plan-error":
  # A default or actually refused planner contains no successfully verified report list.
  let outcome = if paramStr(1) == "plan-default": default(AvailabilityTransitionResult[
      AvailabilityPlan]) else:
    planAvailability(default(AvailabilitySnapshot), default(ValidatorStateSnapshot), ValidatorCount(
        6), [],
      default(AssuranceParent), StateTime(0), default(AvailabilityTransitionConfig))
  discard outcome.value
of "assignments", "count":
  # Opaque default owners cannot stand in for an empty successful assignment/report collection.
  let plan = default(AvailabilityPlan)
  if paramStr(1) == "assignments": discard plan.assuredAssignments # Requires retained storage.
  else: discard plan.availableReportCount # No fabricated empty list.
of "update-default", "update-error":
  # Failed publication and default results never expose snapshots or plans.
  let outcome = if paramStr(1) == "update-default": default(AvailabilityTransitionResult[
      AvailabilityUpdate]) else:
    advanceAvailabilityState(state, default(ValidatorStateSnapshot), [], default(AssuranceParent),
      StateTime(0), default(AvailabilityTransitionConfig))
  discard outcome.value
of "context-reason":
  # Only the exact selected context/signature refusal has a context reason.
  let outcome = default(AvailabilityTransitionResult[AvailabilityPlan])
  echo outcome.contextError
of "block-availability-reason":
  # A default block result cannot expose availability failure details.
  let outcome = default(BlockTransitionResult)
  discard outcome.availabilityError
else:
  quit(3) # Unsupported selectors cannot satisfy an intended assertion failure.
