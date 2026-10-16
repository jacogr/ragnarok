## Safe code cannot bypass private/read-only header state through error.
import ../../../src/codec/header
var value = default(HeaderResult[int])
value.error = HeaderError.None
