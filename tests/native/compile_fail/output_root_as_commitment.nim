## Trie roots cannot silently become service output commitments.
import ../../../src/[state_outputs, state_layout]
let value = AccumulationOutput(commitment: default(StateNodeHash))
discard value
