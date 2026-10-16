## A regular leaf value digest is not a child-node identity.
import ../../../src/codec/state_layout
var wrong: StateValueHash
var right: StateNodeHash
discard encodeStateBranch(wrong, right)
