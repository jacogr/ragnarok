## External callers cannot expose, forge or mutate private chapter-14/15 result/owner storage.
import ../../../src/codec/[state_workqueues, state_trie]
discard WorkQueueResult[WorkQueueInfo](status: WorkQueueError.None)
