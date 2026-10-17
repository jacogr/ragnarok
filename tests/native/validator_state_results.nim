## Default/failed publication outcomes reject snapshot extraction through the intended checked contract.
import std/[assertions, cmdline, syncio]
import ../../src/state/[validator_state, store]
import ../../src/codec/state_safrole

var state = default(StateStore)
let outcome = if paramStr(1) == "default": default(ValidatorStateResult) else:
  rotateValidatorState(state, StateTime(1), [], default(
      ValidatorTransitionConfig)) # Invalid policy is an actual typed failure.
assert paramStr(1) in ["default", "error"] # Unknown selectors cannot stand in for result misuse.
assert outcome.error == (if paramStr(1) == "default": ValidatorStateError.Uninitialized else: ValidatorStateError.InvalidConfig)
echo outcome.value.commitment.entries
