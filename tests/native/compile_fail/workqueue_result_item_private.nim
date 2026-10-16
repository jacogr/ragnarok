## External callers cannot expose, forge or mutate private chapter-14/15 result/owner storage.
import ../../../src/codec/[state_workqueues, state_trie]
let value = default(WorkQueueResult[ReadyItemInfo])
discard value.completed
