## Isolated extraction guards distinguish default and real failed plans from unrelated crashes.
import std/[assertions, cmdline, syncio]
import ../../src/state/validators
import ../../src/codec/state_safrole
from ../../src/codec/header import EpochSlots

let outcome = if paramStr(1) == "default": default(ValidatorRotationResult) else:
    planValidatorRotation(default(ValidatorStateSnapshot), default(ValidatorStateSnapshot),
        default(ValidatorStateSnapshot), default(ValidatorStateSnapshot), StateTime(0), StateTime(1),
        EpochSlots(0), [], default(ValidatorRotationConfig))
assert paramStr(1) in ["default", "error"] # Unknown selectors are harness errors, never valid rejection evidence.
assert outcome.error == (if paramStr(1) == "default": ValidatorRotationError.Uninitialized else: ValidatorRotationError.InvalidConfig)
echo outcome.value.epochChanged
