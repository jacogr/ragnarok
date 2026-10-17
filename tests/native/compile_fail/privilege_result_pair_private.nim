## External callers cannot expose, forge or mutate private chapter-12 results or owner storage.
import ../../../src/codec/[state_privileges, state_trie]
let value = default(PrivilegeResult[AlwaysAccumulate])
discard value.completed
