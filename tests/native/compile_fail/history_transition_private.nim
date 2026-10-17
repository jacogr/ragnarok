## Proposed history payloads remain private even on default results.
import ../../../src/state/history
import ../../../src/codec/state_trie
let hidden = default(HistoryTransitionResult[StateEntry])
discard hidden.completed
