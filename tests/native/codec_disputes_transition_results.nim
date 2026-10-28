# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused plans and nonselected block-stage reasons cannot expose successful payloads.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/cmdline
import std/syncio
import ../../src/state/disputes as state_disputes
import ../../src/state/block_transition as state_block_transition
import ../../src/state/block_admission as state_block_admission
import ../../src/state/safrole_transition as state_safrole_transition
import ../../src/state/store as state_store
import ../../src/state/availability as state_availability
import ../../src/codec/disputes as codec_disputes
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/header as codec_header
var state = default(StateStore)
case paramStr(1)
of "plan-default", "plan-error":
  # Neither a default result nor an actual invalid-input failure contains a successful plan.
  let outcome = if paramStr(1) == "plan-default": default(DisputesResult[DisputesPlan]) else:
    planDisputes(default(StateStoreSnapshot), default(OwnedDisputes), default(DisputesConfig))
  discard outcome.value
of "judgments", "assignments", "count":
  # Opaque default owners cannot impersonate complete empty chapters or a verified empty marker.
  let plan = default(DisputesPlan)
  case paramStr(1)
  of "judgments": discard plan.disputeJudgments # Requires retained plan storage.
  of "assignments": discard plan.disputeAssignments # Requires retained plan storage.
  else: discard plan.newOffenderCount # No fabricated empty marker.
of "block-default", "block-error":
  # Public composition retains no posterior state after invalid configuration or default selection.
  let outcome = if paramStr(1) == "block-default": default(BlockTransitionResult) else:
    advanceBlockState(state, default(OwnedBlock), default(OwnedHeader), default(
        BlockAdmissionConfig),
      default(DisputesConfig), default(SafroleTransitionConfig), default(AvailabilityTransitionConfig))
  discard outcome.value
of "admission-reason", "disputes-reason", "safrole-reason":
  # Each reason accessor requires its own selected failure, even though all failures omit state.
  let outcome = default(BlockTransitionResult)
  case paramStr(1)
  of "admission-reason": echo outcome.admissionError # Exact AdmissionFailure required.
  of "disputes-reason": echo outcome.disputesError # Exact DisputesFailure required.
  else: discard outcome.safroleError # Exact SafroleFailure required.
else:
  quit(3) # Unsupported selectors must not satisfy an assertion probe.
