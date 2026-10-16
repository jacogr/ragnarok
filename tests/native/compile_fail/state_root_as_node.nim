## A complete trie root cannot silently masquerade as an internal node hash.
import ../../../src/codec/[state_trie, state_layout]
let root = default(StateRoot)
let node = encodeStateBranch(root, root)
discard node
