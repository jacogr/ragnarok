## Successful request payloads remain private behind the guarded result accessor.
import ../../../src/codec/[state_requests, state_trie]
let parsed = default(RequestResult[StateKey])
discard parsed.completed
