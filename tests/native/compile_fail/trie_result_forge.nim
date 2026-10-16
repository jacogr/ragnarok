## External callers cannot expose, retag or fabricate completed trie commitments or child hashes.
import ../../../src/codec/[state_trie, state_layout]
discard StateTrieResult[StateTrieCommitment](status: StateTrieError.None)
