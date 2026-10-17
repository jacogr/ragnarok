## Isolated checked result extraction for default/real failures must reject without publishing progress.
import std/[assertions, cmdline, syncio]
import ../../src/state/[entropy, store]
import ../../src/codec/state_safrole
from ../../src/codec/header import EpochSlots

case paramStr(1)
of "update":
  # A repeated timeslot produces a real failure; default outcomes are also payload-free.
  let outcome = if paramStr(2) == "default": default(EntropyTransitionResult[
      EntropyTimeUpdate]) else:
      advanceEntropyTime(default(StateEntropy), StateTime(1), StateTime(1), default(EntropyInput),
          EpochSlots(12))
  assert outcome.error == (if paramStr(2) == "default": EntropyTransitionError.Uninitialized else: EntropyTransitionError.InvalidSlot)
  echo uint32(outcome.value.time)
of "state":
  # An initialized empty map does not imply zero entropy and a genesis slot.
  let made = newStateStore([], default(StateStoreLimits))
  assert made.error == StateStoreError.None
  var state = made.value
  let outcome = if paramStr(2) == "default": default(EntropyTransitionResult[
      StateStoreSnapshot]) else:
      advanceEntropyTimeState(state, StateTime(1), default(EntropyInput), EpochSlots(12))
  assert outcome.error == (if paramStr(2) == "default": EntropyTransitionError.Uninitialized else: EntropyTransitionError.MissingState)
  echo outcome.value.commitment.entries
else:
  quit(2) # Bad selectors are harness failures rather than accepted contract rejection evidence.
