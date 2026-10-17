## Safe code cannot bypass private/read-only header state through completed.
import ../../../src/codec/header
var value = default(HeaderResult[HeaderRead])
discard value.completed
