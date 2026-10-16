## A caller cannot turn a default failure into a signing credential.
import ../../../src/crypto/[primitives, guarantee]
var parsed = default(GuaranteeMessageResult)
parsed.status = CryptoError.None
