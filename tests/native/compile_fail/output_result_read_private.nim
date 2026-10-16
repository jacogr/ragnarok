## Result success payloads cannot be read outside the guarded accessor.
import ../../../src/codec/[state_outputs, state_trie]
let parsed = default(OutputLogResult[OutputLogRead])
discard parsed.completed
