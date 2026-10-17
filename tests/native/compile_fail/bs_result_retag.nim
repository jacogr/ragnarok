## Failed/default native results cannot be retagged as success.
import ../../../src/bandersnatch/bandersnatch
var parsed = default(BsResult[BsKey])
parsed.status = BsError.None
