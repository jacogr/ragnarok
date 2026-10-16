## External callers cannot expose or fabricate crypto result/secret storage.
import ../../../src/crypto/primitives
var value = default(CryptoResult[Blake2bHash])
value.value = default(Blake2bHash)
