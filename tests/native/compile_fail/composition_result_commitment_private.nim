## Complete composition payloads remain private behind the success accessor.
import ../../../src/codec/[state_composition, state_trie]
let parsed = default(StateCompositionResult[StateTrieCommitment])
discard parsed.completed
