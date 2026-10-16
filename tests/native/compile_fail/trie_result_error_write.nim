## External callers cannot expose, retag or fabricate completed trie commitments or child hashes.
import ../../../src/codec/[state_trie, state_layout]
var value = default(StateTrieResult[StateTrieCommitment])
value.error = StateTrieError.None
