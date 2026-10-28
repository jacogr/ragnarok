# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated extraction guards distinguish default and real failed plans from unrelated crashes.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/assertions
import std/cmdline
import std/syncio
import ../../src/state/validators as state_validators
import ../../src/codec/state_safrole as codec_state_safrole
from ../../src/codec/header as codec_header import EpochSlots

let outcome = if paramStr(1) == "default": default(ValidatorRotationResult) else:
    planValidatorRotation(default(ValidatorStateSnapshot), default(ValidatorStateSnapshot),
        default(ValidatorStateSnapshot), default(ValidatorStateSnapshot), StateTime(0), StateTime(1),
        EpochSlots(0), [], default(ValidatorRotationConfig))
assert paramStr(1) in ["default", "error"] # Unknown selectors are harness errors, never valid rejection evidence.
assert outcome.error == (if paramStr(1) == "default": ValidatorRotationError.Uninitialized else: ValidatorRotationError.InvalidConfig)
echo outcome.value.epochChanged
