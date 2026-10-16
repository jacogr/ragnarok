## External callers cannot expose, forge or mutate private chapter-13 result/owner storage.
import ../../../src/codec/[state_statistics, state_trie]
let value = default(ActivityResult[ActivityInfo])
discard value.completed
