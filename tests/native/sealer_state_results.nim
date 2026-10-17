## Failed/default publication results cannot expose an immutable working-map payload.
import std/[assertions, cmdline, syncio]
import ../../src/state/[sealer_state, sealer_schedule, store]
import ../../src/codec/[state_safrole, state_trie, bounded]

## A real initialized parent deliberately lacks C(4), giving a distinct actual publication refusal.
proc refused(): SealerStateResult =
  let limits = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(1), perValue: ByteLimit(4),
    totalValueBytes: ByteLimit(4), nodes: TrieNodeLimit(10)), writes: ElementLimit(0),
        writeValueBytes: ByteLimit(0))
  let parent = newStateStore(@[timeEntry(StateTime(0))], limits).value.snapshot.value
  var state = default(StateStore)
  selectSafroleScheduleState(state, parent, StateTime(1), default(SealerScheduleConfig))

let outcome = if paramStr(1) == "default": default(SealerStateResult) else:
  refused() # Actual missing-parent-chapter refusal contains no map.
assert paramStr(1) in ["default", "error"] # Unknown selectors cannot stand in for guarded access.
assert outcome.error == (if paramStr(1) == "default": SealerScheduleError.Uninitialized else: SealerScheduleError.MissingState)
echo outcome.value.commitment.entries
