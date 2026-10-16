## A signing transcript is not an Ed25519 signature.
import ../../../src/crypto/[primitives, guarantee]
let value: EdSignature = default(GuaranteeMessage)
discard value
