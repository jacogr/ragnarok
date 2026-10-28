# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## White-box tests observe explicit wipes while bytes are live; no freed memory or private
## runtime state is read.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "crypto_arc_release"}

import ../../support/testing_arc_evidence
import std/assertions
import std/syncio
include ../../../src/crypto/primitives

# Test-only bridge counters contain no secret bytes or retained ARC owners.
proc watch(address: pointer, length: csize_t) {.importc: "ro_watch", cdecl.}
# The observer counts wipes of the exact watched storage address.
proc calls(): cint {.importc: "ro_calls", cdecl.}
# Nonzero public fixtures distinguish real seed storage from an already-cleared temporary.
proc beforeNonzero(): cint {.importc: "ro_before_nonzero", cdecl.}
# Zero checks occur only inside the callback before allocation release.
proc afterZero(): cint {.importc: "ro_after_zero", cdecl.}
# Failure injection applies only to this observer-linked test process.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}

# Select a completed operation before extracting any fixed value or seed handle.
proc checked[T](value: CryptoResult[T]): T =
  assert value.error == CryptoError.None
  value.value

# Return one retained seed while the importer result/local references retire before destruction checks.
proc watchedSeed(): EdSeed =
  var bytes: array[32, byte] = default(array[32, byte])
  for i in 0..<bytes.len: bytes[i] = 0xA5 # Public deterministic fixture bytes, never production secrets.
  result = checked(importSeed(bytes))
  let storage = result.storage
  assert storage != nil
  watch(addr storage.bytes[0], 32)
  for i in 0..<bytes.len: bytes[i] = 0 # Caller storage is independent of the retained seed.

# Wiping must wait for the last alias, then target and cleanse the actual referent exactly once.
proc lastOwner() =
  var seed = watchedSeed()
  var alias = seed
  seed = default(EdSeed)
  assert calls() == 0
  assert publicKey(alias).error == CryptoError.None
  alias = default(EdSeed)
  assert calls() == 1 and beforeNonzero() == 1 and afterZero() == 1

# Explicit clearing invalidates every alias and zeroes storage before another key/sign operation can use it.
proc explicitClear() =
  var seed = watchedSeed()
  let alias = seed
  clearSeed(seed)
  assert calls() == 1 and beforeNonzero() == 1 and afterZero() == 1
  assert publicKey(alias).error == CryptoError.InvalidSeed
  assert sign(alias, []).error == CryptoError.InvalidSeed
  clearSeed(alias)
  assert calls() == 2 and afterZero() == 2 # Repeated clear is harmless and remains explicit.
  seed = default(EdSeed)

# All foreign backend refusals return typed failures without success payloads; successful recovery is checked too.
proc backendRefusals() =
  let seed = checked(importSeed(default(array[32, byte])))
  fail(15)
  assert blake2b256([]).error == CryptoError.BackendFailure
  assert keccak256([]).error == CryptoError.BackendFailure
  assert publicKey(seed).error == CryptoError.BackendFailure
  assert sign(seed, []).error == CryptoError.BackendFailure
  fail(0)
  let key = checked(publicKey(seed))
  let signature = checked(sign(seed, []))
  assert verify(key, signature, [])
  assert verifyZip215(key, signature, [])
  assert not verifyZip215(key, signature, [byte 1])
  clearSeed(seed)

# Current verification and the explicitly named ZIP215 API agree on cofactored witnesses.
proc zip215Policy() =
  var signatureBytes: array[64, byte] = default(array[64, byte])
  signatureBytes[0] = 1 # R is identity and S is zero.
  let signature = checked(importSignature(signatureBytes))
  let zeroKey = checked(importPublicKey(default(array[32, byte])))             # A has order four.
  assert verifyZip215(zeroKey, signature, [])
  assert verifyZip215(zeroKey, signature, [byte 0])
  assert verify(zeroKey, signature, []) # Current GP activates the cofactored equation.
  var noncanonical: array[32, byte] = default(array[32, byte])
  for i in 0..<32: noncanonical[i] = 255 # y = p+1 encodes identity noncanonically.
  noncanonical[0] = 238
  noncanonical[31] = 127
  let identity = checked(importPublicKey(noncanonical))
  assert verifyZip215(identity, signature, [byte 7])
  var invalid: array[32, byte] = default(array[32, byte])
  invalid[0] = 2 # Current-upgrade null key is not a curve point.
  assert not verifyZip215(checked(importPublicKey(invalid)), signature, [])
  let order: array[32, byte] = [byte 0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58,
    0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10]
  for i in 0..<32: signatureBytes[i+32] = order[i] # S must be strictly below the group order.
  assert not verifyZip215(identity, checked(importSignature(signatureBytes)), [])
  for i in 32..<64: signatureBytes[i] = 0 # Restore the identity equation before testing R encoding.
  for i in 0..<32: signatureBytes[i] = noncanonical[i]
  assert verifyZip215(identity, checked(importSignature(signatureBytes)), [])
  for i in 0..<32: signatureBytes[i] = 0
  signatureBytes[0] = 2 # Invalid R must fail even with a valid identity public key.
  assert not verifyZip215(identity, checked(importSignature(signatureBytes)), [])
  signatureBytes[0] = 1
  signatureBytes[32] = 1 # Nonzero S cannot satisfy the identity equation.
  assert not verifyZip215(identity, checked(importSignature(signatureBytes)), [])

zip215Policy()

lastOwner()
explicitClear()
backendRefusals()
# Warmup excludes allocator setup from the public live-occupancy comparison.
for i in 0..<100: lastOwner(); explicitClear()
let beforeRelease = getOccupiedMem()
# Each scope must release retained aliases and its explicitly erased or automatically destroyed allocation.
for i in 0..<1000: lastOwner(); explicitClear()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("crypto_seeds", 1000, beforeRelease, afterRelease)
echo "CRYPTO_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony crypto: exact-storage final-owner wipe, alias clear, backend refusal and scoped ARC release passed"
