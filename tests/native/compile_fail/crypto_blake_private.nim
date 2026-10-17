## External callers cannot expose or fabricate crypto result/secret storage.
import ../../../src/crypto/primitives
var value = default(CryptoResult[Blake2bHash])
discard value.completed
