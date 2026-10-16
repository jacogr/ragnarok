## A complete trie root cannot silently masquerade as an internal node hash.
import ../../../src/codec/[state_trie, state_layout]
var root: StateRoot
let node = encodeStateBranch(root, root)
discard node
