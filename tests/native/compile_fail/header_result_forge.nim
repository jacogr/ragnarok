## Safe code cannot bypass private/read-only header state through status.
import ../../../src/codec/header
var value = default(HeaderResult[int])
discard HeaderResult[int](status: HeaderError.None)
