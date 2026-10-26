# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JIP-5 validator key derivation from an exact borrowed 32-byte master seed.
## Development indices expand to repeated little-endian uint32 seeds; arbitrary seeds use the same
## domain-separated BLAKE2b-256 derivation. Returned signing owners are opaque and explicitly clearable.
import ./primitives
import ../bandersnatch/bandersnatch

func trivialSeed*(index: uint32): array[32, byte] =
  ## Expand a public development index eight times without hashing; never use as production entropy.
  result = default(array[32, byte])
  for i in 0..<32:
    result[i] = byte((index shr ((i mod 4)*8)) and 255) # Preserve all four little-endian index bytes.

proc deriveSeed(input: openArray[byte], domain: string,
    output: var array[32, byte]): CryptoError {.raises: [], gcsafe.} =
  ## Private fixed-domain composition: ASCII bytes, no terminator, followed by the unmodified seed.
  if input.len != 32:
    return CryptoError.InvalidLength # Refuse before allocation or hashing.
  var message = newSeq[byte](domain.len+32)
  defer: clearSecret(message)
  for i in 0..<domain.len:
    message[i] = byte(domain[i]) # Only the two fixed ASCII domains below call this helper.
  for i in 0..<32:
    message[domain.len+i] = input[i]
  blake2b256(message, output)

proc deriveEd25519Seed*(seed: openArray[byte]): CryptoResult[EdSeed] {.raises: [], gcsafe.} =
  ## Retain the JIP-5 Ed25519 seed in a private wipe-on-release owner; caller retains its master seed.
  var derived = default(array[32, byte])
  defer: clearSecret(derived)
  let reason = deriveSeed(seed, "jam_val_key_ed25519", derived)
  if reason != CryptoError.None:
    return cryptoFailure[EdSeed](reason) # A failed hash never becomes an all-zero signing seed.
  primitives.importSeed(derived)

proc deriveBandersnatchKey*(seed: openArray[byte]): BsResult[BsKey] {.raises: [], gcsafe.} =
  ## Derive the JIP-5 Bandersnatch seed, then use Draft 35 A.3 to create an opaque key.
  var derived = default(array[32, byte])
  defer: clearSecret(derived)
  let reason = deriveSeed(seed, "jam_val_key_bandersnatch", derived)
  if reason != CryptoError.None:
    let failure = if reason == CryptoError.InvalidLength: BsError.InvalidLength else: BsError.BackendFailure
    return bsFailure[BsKey](failure) # No native key is allocated after width/hash refusal.
  importSecretSeed(derived)
