## External callers cannot expose or fabricate crypto result/secret storage.
import ../../../src/crypto/primitives
discard CryptoResult[Blake2bHash](status: CryptoError.None)
