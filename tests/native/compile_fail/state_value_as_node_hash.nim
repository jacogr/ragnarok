## A regular leaf value digest is not a child-node identity.
import ../../../src/codec/state_layout
let wrong = default(StateValueHash)
let right = default(StateNodeHash)
discard encodeStateBranch(wrong, right)
