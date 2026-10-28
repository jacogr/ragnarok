# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native key/setup ownership, fixed-copy imports and failure recovery over the unchanged Rust
## ABI.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "bandersnatch_arc_release"}

import ../../support/testing_arc_evidence
import std/assertions
import std/syncio
import ../../native/nimony_batch_support
import ../../../src/bandersnatch/bandersnatch as bandersnatch_bandersnatch

# Reset attempt/free counters and failure flags without erasing the number of still-live native allocations.
proc reset(flags: cint) {.importc: "bo_reset", cdecl.}
# Each counter reports an actual call through the original Rust allocator/destructor.
proc keyNews(): cint {.importc: "bo_key_news", cdecl.}
# Key frees must occur once at explicit close or final ARC release, never both.
proc keyFrees(): cint {.importc: "bo_key_frees", cdecl.}
# Setup constructors use the real pinned embedded SRS.
proc setupNews(): cint {.importc: "bo_setup_news", cdecl.}
# Setup frees must pair with their original allocator.
proc setupFrees(): cint {.importc: "bo_setup_frees", cdecl.}
# Live counts remain observable across resets, so tests cannot conceal a leaked native allocation.
proc liveKeys(): cint {.importc: "bo_live_keys", cdecl.}
# No native address or freed/secret memory is exposed to this observer.
proc liveSetups(): cint {.importc: "bo_live_setups", cdecl.}

# Published draft-29 vector one supplies an independent canonical public encoding, not native round-trip output.
proc publicFixture(): array[32, byte] =
  const text = "a1b1da71cc4682e159b7da23050d8b6261eb11a3247c89b07ef56ccd002fd38b"
  result = default(array[32, byte])
  # Copy exactly one canonical public point's original bytes.
  for i in 0..<32: result[i] = octet(text[2*i..2*i+1])

# Return a native key after its creator's stack, source bytes and result temporary have left scope.
proc escapedKey(): BsKey =
  var scalar = default(array[32, byte])
  scalar[0] = 1
  let imported = importScalar(scalar)
  assert imported.error == BsError.None
  result = imported.value
  scalar[0] = 2 # Rust must have copied the scalar, not retained this borrowed buffer.

# Observe shared close, replacement and automatic last-owner release using only public owner handles.
proc keys() =
  reset(0)
  close(default(BsKey))
  assert keyFrees() == 0
  block:
    var key = escapedKey()
    let alias = key
    assert keyNews() == 1 and liveKeys() == 1
    let expected = array[32, byte](publicKey(alias).value)
    key = default(BsKey) # Replacing one handle must not free an allocation retained by another.
    assert keyFrees() == 0 and array[32, byte](publicKey(alias).value) == expected
  assert keyFrees() == 1 and liveKeys() == 0
  block:
    let key = escapedKey()
    let alias = key
    close(key)
    assert publicKey(alias).error == BsError.InvalidOwner
    close(alias) # Explicit close invalidates all aliases and remains idempotent.
  assert keyNews() == 2 and keyFrees() == 2 and liveKeys() == 0
  assert importScalar([]).error == BsError.InvalidLength
  assert importScalar(default(array[32, byte])).error == BsError.InvalidEncoding
  assert liveKeys() == 0 # Failed imports cannot create a hidden allocation.
  reset(1)
  var scalar = default(array[32, byte])
  scalar[0] = 1
  assert importScalar(scalar).error == BsError.BackendFailure
  assert keyNews() == 1 and keyFrees() == 0 and liveKeys() == 0
  reset(0)
  block:
    let recovered = importScalar(scalar).value
    assert publicKey(recovered).error == BsError.None # A refused import must not poison later ownership.
  assert liveKeys() == 0 and keyFrees() == 1

# Setups follow the same shared lifetime rules, independently of scalar ownership and allocator kind.
proc setups() =
  reset(0)
  close(default(BsSetup))
  assert setupFrees() == 0
  # Reject host extremes before converting to native size_t or constructing a domain.
  for capacity in [low(int), -1, 0, 1024, high(int)]:
    assert newSetup(capacity).error == BsError.InvalidLength
  assert setupNews() == 0
  block:
    var setup = newSetup(8).value
    let alias = setup
    setup = default(BsSetup) # The alias retains the real SRS-backed native allocation.
    assert setupFrees() == 0 and liveSetups() == 1
    assert commitRing(alias, publicFixture()).error == BsError.None
  assert setupNews() == 1 and setupFrees() == 1 and liveSetups() == 0
  block:
    let setup = newSetup(8).value
    let alias = setup
    close(setup)
    assert commitRing(alias, publicFixture()).error == BsError.InvalidOwner
    close(alias) # Last ARC release must observe that explicit close already released the native storage.
  assert setupNews() == 2 and setupFrees() == 2 and liveSetups() == 0
  reset(2)
  assert newSetup(8).error == BsError.BackendFailure
  assert setupNews() == 1 and setupFrees() == 0 and liveSetups() == 0
  reset(0)
  block:
    let recovered = newSetup(8).value
    assert commitRing(recovered, publicFixture()).error == BsError.None
  assert setupNews() == 1 and setupFrees() == 1 and liveSetups() == 0

# Fixed proof/root imports validate width only; independent cryptographic verification remains a later slice.
proc fixedCopies() =
  var source = publicFixture()
  let key = importPublicKey(source)
  assert key.error == BsError.None
  source[0] = source[0] xor 1
  assert array[32, byte](key.value) == publicFixture()
  assert importPublicKey([]).error == BsError.InvalidLength
  var signature = default(array[96, byte])
  var proof = default(array[784, byte])
  var root = default(array[144, byte])
  signature[0] = 11
  proof[0] = 12
  root[0] = 13
  let s = importSignature(signature)
  let p = importRingProof(proof)
  let r = importRingRoot(root)
  signature[0] = 0
  proof[0] = 0
  root[0] = 0
  assert array[96, byte](s.value)[0] == 11
  assert array[784, byte](p.value)[0] == 12
  assert array[144, byte](r.value)[0] == 13
  # Both shorter and longer imports must reject rather than truncate or pad.
  for length in [0, 95, 97]: assert importSignature(newSeq[byte](length)).error ==
      BsError.InvalidLength
  for length in [0, 783, 785]: assert importRingProof(newSeq[byte](length)).error ==
      BsError.InvalidLength
  for length in [0, 143, 145]: assert importRingRoot(newSeq[byte](length)).error ==
      BsError.InvalidLength
  let normalized = normalizeRing(publicFixture())
  assert normalized.error == BsError.None
  var copied = normalized.value
  copied[0] = copied[0] xor 1
  assert normalized.value[0] == publicFixture()[0] # Returned sequence copies do not expose retained mutable storage.

keys()
setups()
fixedCopies()
# Warm up only the fast scalar/import workload; expensive SRS setup release is observed separately above.
for i in 0..<20: keys(); fixedCopies()
let beforeRelease = getOccupiedMem()
# Every scope must release its last scalar reference and all fixed/import sequence temporaries.
for i in 0..<1000: keys(); fixedCopies()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease and liveKeys() == 0 and liveSetups() == 0
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("bandersnatch_owners", 1000, beforeRelease, afterRelease)
echo "BANDERSNATCH_OWNERS_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony Bandersnatch: key/setup close, alias/final release, fixed imports and refusal recovery passed"
