## The public message accessor does not export mutable result storage.
import ../../../src/crypto/[primitives, guarantee]
var parsed = default(GuaranteeMessageResult)
parsed.value = default(GuaranteeMessage)
