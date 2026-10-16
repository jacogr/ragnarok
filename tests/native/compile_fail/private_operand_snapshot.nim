## External code cannot mutate immutable operand backing bytes or private spans.
import ../../../src/codec/c2_records
var owner: OwnedOperand
discard owner.data
