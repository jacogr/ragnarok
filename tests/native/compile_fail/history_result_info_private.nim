## External callers cannot expose, forge or mutate private chapter-3 results, owners or peak alternatives.
import ../../../src/codec/[state_history, state_trie]
let value = default(HistoryResult[HistoryInfo])
discard value.completed
