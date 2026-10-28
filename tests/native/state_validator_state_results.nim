# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/failed publication outcomes reject snapshot extraction through the intended checked
## contract.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/assertions
import std/cmdline
import std/syncio
import ../../src/state/validator_state as state_validator_state
import ../../src/state/store as state_store
import ../../src/codec/state_safrole as codec_state_safrole

var state = default(StateStore)
let outcome = if paramStr(1) == "default": default(ValidatorStateResult) else:
  rotateValidatorState(state, StateTime(1), [], default(
      ValidatorTransitionConfig)) # Invalid policy is an actual typed failure.
assert paramStr(1) in ["default", "error"] # Unknown selectors cannot stand in for result misuse.
assert outcome.error == (if paramStr(1) == "default": ValidatorStateError.Uninitialized else: ValidatorStateError.InvalidConfig)
echo outcome.value.commitment.entries
