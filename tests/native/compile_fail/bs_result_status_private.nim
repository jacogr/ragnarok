## The public reason is read-only and raw result status stays private.
import ../../../src/bandersnatch/bandersnatch
let parsed = default(BsResult[BsKey])
discard parsed.status
