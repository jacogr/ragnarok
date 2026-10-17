## External callers cannot expose or fabricate crypto result/secret storage.
import ../../../src/crypto/primitives
let value = default(EdSeed)
discard value.storage
