## Successful signing results cannot be manufactured by object construction.
import ../../../src/crypto/[primitives, guarantee]
discard GuaranteeMessageResult(status: CryptoError.None, completed: default(GuaranteeMessage))
