# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and actually refused schedule selections cannot expose an immutable candidate
## payload.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/assertions
import std/cmdline
import std/syncio
import ../../src/state/sealer_schedule as state_sealer_schedule
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/codec/state_consensus as codec_state_consensus

let outcome = if paramStr(1) == "default": default(SealerScheduleResult) else:
  selectSafroleSchedule([], [], [], StateTime(0), StateTime(1), default(StateEntropyWord),
    default(SealerScheduleConfig)) # Invalid configuration produces a real failed result.
assert paramStr(1) in ["default", "error"] # Unknown selectors must fail separately from payload protection.
assert outcome.error == (if paramStr(1) == "default": SealerScheduleError.Uninitialized else: SealerScheduleError.InvalidConfig)
echo safroleInfo(outcome.value).value.validators
