## External callers cannot expose or fabricate crypto result/secret storage.
import ../../../src/crypto/primitives
var value = default(CryptoResult[EdPublicKey])
discard value.completed
