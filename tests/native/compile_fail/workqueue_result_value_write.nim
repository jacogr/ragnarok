## External callers cannot expose, forge or mutate private chapter-14/15 result/owner storage.
import ../../../src/codec/[state_workqueues, state_trie]
var value = default(WorkQueueResult[WorkQueueInfo])
value.value = default(WorkQueueInfo)
