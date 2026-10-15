## GP v0.8.0 Cryptography: raw-byte Blake2b-256, legacy Keccak-256 and ordinary RFC 8032 Ed25519.
## Inputs are borrowed synchronously; outputs own bytes. Domain/codec composition belongs to callers.
const Header = "../../native/crypto/primitive_bridge.h"

# Erase owned seed storage with the backend's explicit wipe, including on last ARC release.
proc wipe(bytes: pointer, length: csize_t) {.importc: "rc_wipe", header: Header, cdecl, raises: [], gcsafe.}
# The bridge owns only ephemeral native scratch and copies a complete 32-byte digest to output.
proc nativeBlake(data: pointer, length: csize_t, output: pointer): cint {.importc: "rc_blake2b256",
    header: Header, cdecl, raises: [], gcsafe.}
# Legacy Keccak parameters and opaque native state stay on the C stack.
proc nativeKeccak(data: pointer, length: csize_t, output: pointer): cint {.importc: "rc_keccak256",
    header: Header, cdecl, raises: [], gcsafe.}
# Derive public bytes from a borrowed 32-byte seed; expanded secret scratch is erased before return.
proc nativePublic(seed, output: pointer): cint {.importc: "rc_ed_public", header: Header, cdecl,
    raises: [], gcsafe.}
# Sign an exact raw message; failure leaves no public signature value and native secret scratch is wiped.
proc nativeSign(seed, data: pointer, length: csize_t,
    output: pointer): cint {.importc: "rc_ed_sign", header: Header, cdecl, raises: [], gcsafe.}
# Report the pinned BoringSSL verification verdict without inventing an application domain/prehash mode.
proc nativeVerify(key, signature, data: pointer, length: csize_t): cint {.importc: "rc_ed_verify",
    header: Header, cdecl, raises: [], gcsafe.}

type
  # Nominal 32-byte Blake2b digest; not interchangeable with a Keccak hash or signing key.
  Blake2bHash* = distinct array[32, byte]
  # Nominal Ethereum-style legacy Keccak-256 digest, separate from SHA3-256.
  KeccakHash* = distinct array[32, byte]
  # Owned encoded public-key bytes; import checks size, verification checks backend point/signature policy.
  EdPublicKey* = distinct array[32, byte]
  # Owned ordinary Ed25519 signature bytes, never an Ed25519ph or contextual signature.
  EdSignature* = distinct array[64, byte]
  # Typed failures; default results are failures and contain no payload fields.
  CryptoError* {.pure.} = enum
    Uninitialized, None, InvalidLength, InvalidSeed, AllocationFailure, BackendFailure
  # Generic checked result: successful fixed bytes/seed owners exist only in the None alternative.
  CryptoResult*[T] = object
    case error*: CryptoError
    of CryptoError.None:
      # Only completed operations expose their owned value.
      value*: T
    else:
      # Failed imports/signing have no default key/signature to use accidentally.
      discard
  # Private acyclic ARC storage, shared only through opaque handles; clearing invalidates all aliases.
  SeedStorage = object
    bytes: array[32, byte]
    alive: bool
  # Opaque retained seed handle; safe callers cannot inspect or modify secret bytes.
  EdSeed* = object
    storage: ref SeedStorage

# Last-owner destruction explicitly erases retained bytes without depending on ordinary assignment optimization.
proc `=destroy`(storage: var SeedStorage) {.raises: [], gcsafe.} =
  wipe(addr storage.bytes[0], 32)

# Select a borrowed input pointer only while its original open array is alive; nil represents an empty message.
proc dataPointer(input: openArray[byte]): pointer {.raises: [], gcsafe.} =
  # Empty arrays have no element address to evaluate.
  if input.len == 0: return nil
  unsafeAddr input[0]

# Retain a private seed copy; no reference to the caller's original array survives this operation.
proc importSeed*(input: openArray[byte]): CryptoResult[EdSeed] {.raises: [], gcsafe.} =
  # A seed has exact RFC 8032 width, including when all its bytes are zero.
  if input.len != 32: return CryptoResult[EdSeed](error: CryptoError.InvalidLength)
  var storage: ref SeedStorage
  new(storage)
  # Explicit deep copying prevents input mutation from altering future signatures.
  for i in 0..<32: storage.bytes[i] = input[i]
  storage.alive = true
  CryptoResult[EdSeed](error: CryptoError.None, value: EdSeed(storage: storage))

# Erase and invalidate all retained aliases; ARC frees storage when the last opaque handle is released.
proc clearSeed*(seed: EdSeed) {.raises: [], gcsafe.} =
  # Clearing a default owner is harmless and cannot fabricate an initialized zero seed.
  if seed.storage.isNil: return
  wipe(addr seed.storage.bytes[0], 32)
  seed.storage.alive = false

# Import fixed encoded public-key bytes; this is a size check, not a claim of subgroup membership.
proc importPublicKey*(input: openArray[byte]): CryptoResult[EdPublicKey] {.raises: [], gcsafe.} =
  # Wrong widths fail before any usable key value is constructed.
  if input.len != 32: return CryptoResult[EdPublicKey](error: CryptoError.InvalidLength)
  var value: array[32, byte]
  for i in 0..<32: value[i] = input[i]
  CryptoResult[EdPublicKey](error: CryptoError.None, value: EdPublicKey(value))

proc importSignature*(input: openArray[byte]): CryptoResult[EdSignature] {.raises: [], gcsafe.} =
  # Failed width checks expose no signature or padding bytes.
  if input.len != 64: return CryptoResult[EdSignature](error: CryptoError.InvalidLength)
  var value: array[64, byte]
  # Preserve every public signature byte without narrowing or truncation.
  for i in 0..<64: value[i] = input[i]
  CryptoResult[EdSignature](error: CryptoError.None, value: EdSignature(value))

# Hash raw bytes with a 32-byte Blake2b parameter; no implicit codec transform or domain prefix is added.
proc blake2b256*(input: openArray[byte]): CryptoResult[Blake2bHash] {.raises: [], gcsafe.} =
  var output: array[32, byte]
  # Native failure never exposes the temporary default digest.
  if nativeBlake(dataPointer(input), csize_t(input.len), addr output[0]) != 1:
    return CryptoResult[Blake2bHash](error: CryptoError.BackendFailure)
  CryptoResult[Blake2bHash](error: CryptoError.None, value: Blake2bHash(output))

# Hash raw bytes with legacy Keccak-256 (suffix 0x01), independently of SHA3's 0x06 suffix.
proc keccak256*(input: openArray[byte]): CryptoResult[KeccakHash] {.raises: [], gcsafe.} =
  var output: array[32, byte]
  # Backend parameter/setup failure produces no usable digest.
  if nativeKeccak(dataPointer(input), csize_t(input.len), addr output[0]) != 1:
    return CryptoResult[KeccakHash](error: CryptoError.BackendFailure)
  CryptoResult[KeccakHash](error: CryptoError.None, value: KeccakHash(output))

# Derive public bytes using a live retained seed; native expanded key material stays ephemeral.
proc publicKey*(seed: EdSeed): CryptoResult[EdPublicKey] {.raises: [], gcsafe.} =
  # Default or cleared seed owners are failures, distinct from an explicitly imported all-zero seed.
  if seed.storage.isNil or not seed.storage.alive: return CryptoResult[EdPublicKey](
      error: CryptoError.InvalidSeed)
  var output: array[32, byte]
  # Do not expose a partial/default public key after a native failure.
  if nativePublic(addr seed.storage.bytes[0], addr output[0]) != 1:
    return CryptoResult[EdPublicKey](error: CryptoError.BackendFailure)
  CryptoResult[EdPublicKey](error: CryptoError.None, value: EdPublicKey(output))

# Sign the exact raw message with ordinary deterministic Ed25519; no implicit hash/domain is applied.
proc sign*(seed: EdSeed, message: openArray[byte]): CryptoResult[EdSignature] {.raises: [], gcsafe.} =
  # A missing/cleared handle cannot silently act as an all-zero private key.
  if seed.storage.isNil or not seed.storage.alive: return CryptoResult[EdSignature](
      error: CryptoError.InvalidSeed)
  var output: array[64, byte]
  # Allocation/backend failures have no signature payload; all expanded secret scratch is wiped in C.
  if nativeSign(addr seed.storage.bytes[0], dataPointer(message), csize_t(message.len), addr output[0]) != 1:
    return CryptoResult[EdSignature](error: CryptoError.BackendFailure)
  CryptoResult[EdSignature](error: CryptoError.None, value: EdSignature(output))

proc verify*(key: EdPublicKey, signature: EdSignature, message: openArray[byte]): bool {.raises: [], gcsafe.} =
  var publicBytes = array[32, byte](key)
  var signatureBytes = array[64, byte](signature)
  nativeVerify(addr publicBytes[0], addr signatureBytes[0], dataPointer(message), csize_t(
      message.len)) == 1
