## Verified output hashes cannot masquerade as public keys.
import ../../../src/bandersnatch/bandersnatch
let value: BsPublicKey = default(BsOutput)
discard value
