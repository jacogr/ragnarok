## A raw digest cannot substitute for the domain-prefixed message.
import ../../../src/crypto/[primitives, guarantee]
let value: GuaranteeMessage = default(Blake2bHash)
discard value
