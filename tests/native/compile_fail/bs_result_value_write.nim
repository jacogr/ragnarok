## Completed result storage is never mutable through the success accessor.
import ../../../src/bandersnatch/bandersnatch
var parsed = default(BsResult[BsKey])
parsed.value = default(BsKey)
