## A 31-octet state key cannot stand in for a complete 32-octet child hash.
import ../../../src/codec/state_layout
var wrong: StateKey
var right: StateNodeHash
discard encodeStateBranch(wrong, right)
