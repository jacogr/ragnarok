import ../../support/arc_evidence
## White-box tests observe explicit wipes while bytes are live; no freed memory or private runtime state is read.
import std/[assertions, syncio]
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
  clearSeed(seed)

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
