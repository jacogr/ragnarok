## A truncated left commitment cannot implicitly become a complete child-node hash.
import ../../../src/state_layout
var wrong: LeftChildCommitment
var right: StateNodeHash
discard encodeStateBranch(wrong, right)
