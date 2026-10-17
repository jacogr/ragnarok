## Callers cannot bypass private/read-only Boolean and bitstring result state.
import ../../../src/codec/bitstrings
var value = default(BitResult[BitsRead])
discard value.completed
