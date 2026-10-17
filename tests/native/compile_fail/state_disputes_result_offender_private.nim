## External callers cannot access or forge private chapter-5 results or retained storage.
import ../../../src/codec/[state_disputes, state_trie]
let value = default(DisputeStateResult[OffenderKey])
discard value.completed
