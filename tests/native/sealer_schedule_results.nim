## Default and actually refused schedule selections cannot expose an immutable candidate payload.
import std/[assertions, cmdline, syncio]
import ../../src/state/sealer_schedule
import ../../src/codec/[state_safrole, state_consensus]

let outcome = if paramStr(1) == "default": default(SealerScheduleResult) else:
  selectSafroleSchedule([], [], [], StateTime(0), StateTime(1), default(StateEntropyWord),
    default(SealerScheduleConfig)) # Invalid configuration produces a real failed result.
assert paramStr(1) in ["default", "error"] # Unknown selectors must fail separately from payload protection.
assert outcome.error == (if paramStr(1) == "default": SealerScheduleError.Uninitialized else: SealerScheduleError.InvalidConfig)
echo safroleInfo(outcome.value).value.validators
