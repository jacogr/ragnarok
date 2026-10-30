# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP v0.8.0 Cryptography: raw-byte Blake2b-256, legacy Keccak-256 and ordinary RFC 8032
## Ed25519. Inputs are borrowed synchronously; outputs own bytes. Domain/codec composition
## belongs to callers.
##
## Exposes typed seeds, public keys and signatures, explicit seed clearing, hashing, key
## derivation, signing and verification.

const Header = "primitive_bridge.h"

proc wipe(bytes: pointer, length: csize_t) {.importc: "rc_wipe", header: Header, cdecl, raises: [], gcsafe.}
  ## Erase owned seed storage with the backend's explicit wipe, including on last ARC release.

proc nativeBlake(data: pointer, length: csize_t, output: pointer): cint {.importc: "rc_blake2b256",
    header: Header, cdecl, raises: [], gcsafe.}
  ## The bridge owns only ephemeral native scratch and copies a complete 32-byte digest to output.

proc nativeKeccak(data: pointer, length: csize_t, output: pointer): cint {.importc: "rc_keccak256",
    header: Header, cdecl, raises: [], gcsafe.}
  ## Legacy Keccak parameters and opaque native state stay behind the synchronous Rust ABI.

proc nativePublic(seed, output: pointer): cint {.importc: "rc_ed_public", header: Header, cdecl,
    raises: [], gcsafe.}
  ## Derive public bytes from a borrowed 32-byte seed; expanded secret scratch is erased before return.

proc nativeSign(seed, data: pointer, length: csize_t,
    output: pointer): cint {.importc: "rc_ed_sign", header: Header, cdecl, raises: [], gcsafe.}
  ## Sign an exact raw message; failure leaves no public signature value and native secret scratch is wiped.

proc nativeVerify(key, signature, data: pointer, length: csize_t): cint {.importc: "rc_ed_verify",
    header: Header, cdecl, raises: [], gcsafe.}
  ## Apply current Gray Paper ZIP215 rules without adding an application domain or prehash mode.

proc nativeVerifyZip215(key, signature, data: pointer,
    length: csize_t): cint {.importc: "rc_ed_verify_zip215",

header: Header, cdecl, raises: [], gcsafe.}
  ## Named ZIP215 capability shares the same maintained verifier selected by the current protocol.

type
  Blake2bHash* = distinct array[32, byte] ## Nominal 32-byte Blake2b digest; not interchangeable with a Keccak hash or signing key.
  KeccakHash* = distinct array[32, byte] ## Nominal Ethereum-style legacy Keccak-256 digest, separate from SHA3-256.
  EdPublicKey* = distinct array[32, byte] ## Owned encoded public-key bytes; import checks size, verification checks backend point/signature policy.
  EdSignature* = distinct array[64, byte] ## Owned ordinary Ed25519 signature bytes, never an Ed25519ph or contextual signature.
  CryptoError* {.pure.} = enum ## Typed failures; default results are failures and contain no payload fields.
    Uninitialized, None, InvalidLength, InvalidSeed, AllocationFailure, BackendFailure
  CryptoResult*[T] = object ## Generic checked result: successful fixed bytes/seed owners exist only in the None alternative.
    case status: CryptoError
    of None:
      # Only completed operations expose their owned value.
      completed: T
    else:
      # Failed imports/signing have no default key/signature to use accidentally.
      discard
  # Private acyclic ARC storage, shared only through opaque handles; clearing invalidates all aliases.
  SeedStorage = object
    bytes: array[32, byte]
    alive: bool
  # ARC references share one private storage object without copying secret bytes.
  SeedData = ref SeedStorage
  EdSeed* = object ## Opaque retained seed handle; safe callers cannot inspect or modify secret bytes.
    storage: nil SeedData

func error*[T](value: CryptoResult[T]): CryptoError =
  ## Outcomes are read-only; failed/default imports and backend calls carry no usable value.
  value.status

func cryptoFailure*[T](reason: CryptoError): CryptoResult[T] {.requires: reason !=
    CryptoError.None.} =
  ## Compose a typed failure without exposing private result fields or permitting fabricated success.
  CryptoResult[T](status: reason)

func value*[T](value: CryptoResult[T]): T {.inline, requires: value.status == CryptoError.None.} =
  ## Supported success contracts guard all fixed outputs and opaque seed handles.
  value.completed

# Last-owner destruction explicitly erases retained bytes without depending on ordinary assignment optimization.
proc `=wasMoved`(storage: var SeedStorage) {.raises: [], gcsafe.} =
  ## Erase the transferred secret scratch without releasing the destination owner.
  wipe(cast[pointer](addr storage.bytes[0]), 32)
  storage.alive = false

proc `=destroy`(storage: SeedStorage) {.raises: [], gcsafe.} =
  ## Erase retained secret bytes when the seed storage owner is destroyed.
  wipe(cast[pointer](unsafeAddr storage.bytes[0]), 32)

proc dataPointer(input: openArray[byte]): pointer {.raises: [], gcsafe.} =
  ## Select a borrowed input pointer only while its original open array is alive; nil represents an empty message.
  # Empty arrays have no element address to evaluate.
  if input.len == 0: return nil
  unsafeAddr input[0]

proc clearSecret*(input: var openArray[byte]) {.raises: [], gcsafe.} =
  ## Explicitly erase caller-owned secret scratch; no pointer survives this synchronous call.
  if input.len > 0:
    wipe(addr input[0], csize_t(input.len)) # Empty buffers have no first-element address.

proc importSeed*(input: openArray[byte]): CryptoResult[EdSeed] {.raises: [], gcsafe.} =
  ## Retain a private seed copy; no reference to the caller's original array survives this operation.
  # A seed has exact RFC 8032 width, including when all its bytes are zero.
  if input.len != 32: return CryptoResult[EdSeed](status: CryptoError.InvalidLength)
  let storage = SeedData(bytes: default(array[32, byte]), alive: true)
  # Explicit deep copying prevents input mutation from altering future signatures.
  for i in 0..<32: storage.bytes[i] = input[i]
  CryptoResult[EdSeed](status: CryptoError.None, completed: EdSeed(storage: storage))

proc clearSeed*(seed: EdSeed) {.raises: [], gcsafe.} =
  ## Erase and invalidate all retained aliases; ARC frees storage when the last opaque handle is released.
  let storage = seed.storage
  # Clearing a default owner is harmless and cannot fabricate an initialized zero seed.
  if storage == nil: return
  wipe(addr storage.bytes[0], 32)
  storage.alive = false

proc importPublicKey*(input: openArray[byte]): CryptoResult[EdPublicKey] {.raises: [], gcsafe.} =
  ## Import fixed encoded public-key bytes; this is a size check, not a claim of subgroup membership.
  # Wrong widths fail before any usable key value is constructed.
  if input.len != 32: return CryptoResult[EdPublicKey](status: CryptoError.InvalidLength)
  var value: array[32, byte] = default(array[32, byte])
  # Copy public input bytes without retaining caller storage.
  for i in 0..<32: value[i] = input[i]
  CryptoResult[EdPublicKey](status: CryptoError.None, completed: EdPublicKey(value))

proc importSignature*(input: openArray[byte]): CryptoResult[EdSignature] {.raises: [], gcsafe.} =
  ## Import exact public signature bytes without validating a signature equation or adding padding.
  # Failed width checks expose no signature or padding bytes.
  if input.len != 64: return CryptoResult[EdSignature](status: CryptoError.InvalidLength)
  var value: array[64, byte] = default(array[64, byte])
  # Preserve every public signature byte without narrowing or truncation.
  for i in 0..<64: value[i] = input[i]
  CryptoResult[EdSignature](status: CryptoError.None, completed: EdSignature(value))

proc blake2b256*(input: openArray[byte]): CryptoResult[Blake2bHash] {.raises: [], gcsafe.} =
  ## Hash raw bytes with a 32-byte Blake2b parameter; no implicit codec transform or domain prefix is added.
  var output: array[32, byte] = default(array[32, byte])
  # Native failure never exposes the temporary default digest.
  if nativeBlake(dataPointer(input), csize_t(input.len), addr output[0]) != 1:
    return CryptoResult[Blake2bHash](status: CryptoError.BackendFailure)
  CryptoResult[Blake2bHash](status: CryptoError.None, completed: Blake2bHash(output))

proc blake2b256*(input: openArray[byte], output: var array[32, byte]): CryptoError {.raises: [], gcsafe.} =
  ## Hash into caller-owned scratch so secret derivation can erase the digest without result copies.
  if nativeBlake(dataPointer(input), csize_t(input.len), addr output[0]) != 1:
    return CryptoError.BackendFailure # The native ABI leaves output unchanged on refusal.
  CryptoError.None

proc exportPkcs8*(seed: EdSeed): CryptoResult[array[48, byte]] {.raises: [], gcsafe.} =
  ## Explicitly export unencrypted RFC 8410 Ed25519 PKCS8 DER; callers must erase returned secret bytes.
  let storage = seed.storage
  if storage == nil or not storage.alive:
    return CryptoResult[array[48, byte]](status: CryptoError.InvalidSeed)
  var encoded = default(array[48, byte])
  const Prefix = [0x30'u8, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06,
    0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20]
  for i in 0..<16:
    encoded[i] = Prefix[i] # Fixed algorithm identifier and nested 32-byte OCTET STRING.
  for i in 0..<32:
    encoded[i+16] = storage.bytes[i] # The export owns its bytes and never borrows the seed owner.
  CryptoResult[array[48, byte]](status: CryptoError.None, completed: encoded)

proc keccak256*(input: openArray[byte]): CryptoResult[KeccakHash] {.raises: [], gcsafe.} =
  ## Hash raw bytes with legacy Keccak-256 (suffix 0x01), independently of SHA3's 0x06 suffix.
  var output: array[32, byte] = default(array[32, byte])
  # Backend parameter/setup failure produces no usable digest.
  if nativeKeccak(dataPointer(input), csize_t(input.len), addr output[0]) != 1:
    return CryptoResult[KeccakHash](status: CryptoError.BackendFailure)
  CryptoResult[KeccakHash](status: CryptoError.None, completed: KeccakHash(output))

proc publicKey*(seed: EdSeed): CryptoResult[EdPublicKey] {.raises: [], gcsafe.} =
  ## Derive public bytes using a live retained seed; native expanded key material stays ephemeral.
  let storage = seed.storage
  # Default or cleared seed owners are failures, distinct from an explicitly imported all-zero seed.
  if storage == nil or not storage.alive: return CryptoResult[EdPublicKey](
      status: CryptoError.InvalidSeed)
  var output: array[32, byte] = default(array[32, byte])
  # Do not expose a partial/default public key after a native failure.
  if nativePublic(addr storage.bytes[0], addr output[0]) != 1:
    return CryptoResult[EdPublicKey](status: CryptoError.BackendFailure)
  CryptoResult[EdPublicKey](status: CryptoError.None, completed: EdPublicKey(output))

proc sign*(seed: EdSeed, message: openArray[byte]): CryptoResult[EdSignature] {.raises: [], gcsafe.} =
  ## Sign the exact raw message with ordinary deterministic Ed25519; no implicit hash/domain is applied.
  let storage = seed.storage
  # A missing/cleared handle cannot silently act as an all-zero private key.
  if storage == nil or not storage.alive: return CryptoResult[EdSignature](
      status: CryptoError.InvalidSeed)
  var output: array[64, byte] = default(array[64, byte])
  # Allocation/backend failures have no signature payload; all expanded secret scratch is wiped by Rust drop guards.
  if nativeSign(addr storage.bytes[0], dataPointer(message), csize_t(message.len), addr output[0]) != 1:
    return CryptoResult[EdSignature](status: CryptoError.BackendFailure)
  CryptoResult[EdSignature](status: CryptoError.None, completed: EdSignature(output))

proc verify*(key: EdPublicKey, signature: EdSignature, message: openArray[byte]): bool {.raises: [], gcsafe.} =
  ## Apply ZIP215 to exact copied key/signature encodings and a borrowed raw message.
  var publicBytes = array[32, byte](key)
  var signatureBytes = array[64, byte](signature)
  nativeVerify(addr publicBytes[0], addr signatureBytes[0], dataPointer(message), csize_t(
      message.len)) == 1

proc verifyZip215*(key: EdPublicKey, signature: EdSignature, message: openArray[
    byte]): bool {.raises: [], gcsafe.} =
  ## Explicitly named ZIP215 verification, identical to the current protocol verify policy.
  var publicBytes = array[32, byte](key)
  var signatureBytes = array[64, byte](signature)
  nativeVerifyZip215(addr publicBytes[0], addr signatureBytes[0], dataPointer(message), csize_t(
      message.len)) == 1
