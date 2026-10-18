# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed transcript copies, complete structural preflight and observer-only backend
## refusal/recovery.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import ../../support/arc_evidence
import std/[assertions, syncio]
import ../../../src/crypto/[primitives, assurance_context]
import ../../../src/codec/assurances

# Faults apply only to this test's observer-linked project bridge, with no upstream patches.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
# Refuse the next hash after the specified successful prefix, testing a later record's failure.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
# Count actual hash attempts to distinguish complete preflight from early cryptographic work.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Exercise one complete scope; only public fixed copies survive synchronous calls.
proc exercise() =
  fail(0)
  var parent = default(array[32, byte])
  parent[0] = 7
  let expectedParent = AssuranceParent(parent)
  var bits = default(AssuranceBits)
  bits.bytes[0] = 2
  let config = AssuranceConfig(cores: CoreCount(2), validators: ValidatorCount(6))
  let message = assuranceMessage(expectedParent, bits, config.cores)
  assert message.error == AssuranceContextError.None
  let savedMessage = array[45, byte](message.value)
  var copiedMessage = savedMessage
  copiedMessage[0] = 0
  bits.bytes[0] = 0
  parent[0] = 0
  assert array[45, byte](message.value) == savedMessage # Input/copy mutation cannot alter completed bytes.
  assert savedMessage[0] == byte('j') and savedMessage[12] == byte('e')
  let seed = importSeed(default(array[32, byte])).value
  let key = publicKey(seed).value
  let signature = array[64, byte](sign(seed, savedMessage).value)
  var keys = default(array[6, EdPublicKey])
  # An explicit borrowed key table is selected by validator identity, not record position.
  for i in 0..<keys.len: keys[i] = key
  var values = default(array[2, Assurance])
  # Ordinary signed records are a lifecycle/fault fixture; independent conformance uses OpenSSL separately.
  for i in 0..<values.len:
    values[i].anchor.bytes = array[32, byte](expectedParent)
    values[i].bits.bytes[0] = 2
    values[i].validator = ValidatorIndex(i)
    values[i].signature.bytes = signature
  let savedValues = values
  let savedKeys = keys
  let verified = verifyAssurances(values, config, expectedParent, keys)
  assert verified.error == AssuranceContextError.None and uint64(verified.value) == 2
  assert verifyAssurances([], config, expectedParent, keys).error == AssuranceContextError.None
  assert values == savedValues # Borrowed records remain unchanged.
  # Distinct public-key encodings compare as copied bytes rather than implicitly interchangeable domains.
  for i in 0..<keys.len: assert array[32, byte](keys[i]) == array[32, byte](savedKeys[i])
  # Each structural failure, including a later one behind an invalid earlier signature, precedes all hashes.
  for mode in 0..<9:
    fail(0)
    var changed = savedValues
    var activeConfig = config
    var count = 2
    var keyCount = 6
    var wanted = AssuranceContextError.NonCanonical
    case mode
    of 0:
      activeConfig.cores = CoreCount(high(uint64)) # Invalid profiles reject before width arithmetic.
      wanted = AssuranceContextError.InvalidConfig
    of 1:
      keyCount = 5 # Key-map completeness is required even for empty records.
      count = 0
      wanted = AssuranceContextError.InvalidKeySet
    of 2:
      changed[1].validator = ValidatorIndex(6) # E2 storage does not establish configured membership.
      wanted = AssuranceContextError.InvalidValidator
    of 3: changed[1].validator = ValidatorIndex(0) # Duplicate validators cannot certify two credentials.
    of 4: changed[1].bits.bytes[0] = 4 # Nonzero padding in the final serialized byte is invalid.
    of 5: changed[1].bits.bytes[42] = 1 # Unserialized native storage must also be canonical.
    of 6:
      changed[0].signature.bytes = default(array[64, byte])
      changed[1].anchor.bytes[0] = 99 # A late wrong parent wins over the earlier invalid signature.
      wanted = AssuranceContextError.WrongParent
    of 7:
      changed[0].validator = ValidatorIndex(1)
      changed[1].validator = ValidatorIndex(0) # Strict ascending order is independent of signature validity.
    else:
      changed[0].signature.bytes = default(array[64, byte])
      changed[1].bits.bytes[42] = 1 # A late structural error wins before any crypto attempt.
    let result = verifyAssurances(changed.toOpenArray(0, count-1), activeConfig, expectedParent,
        keys.toOpenArray(0, keyCount-1))
    assert result.error == wanted and hashCalls() == 0
  fail(0)
  let tooMany = default(array[7, Assurance])
  assert verifyAssurances(tooMany, config, expectedParent, keys).error ==
      AssuranceContextError.LimitExceeded
  assert hashCalls() == 0
  # A refused message hash cannot publish zero bytes, and a later refused record cannot publish a partial count.
  fail(1)
  assert assuranceMessage(expectedParent, savedValues[0].bits, config.cores).error ==
      AssuranceContextError.BackendFailure
  assert hashCalls() == 1
  failAfter(1)
  assert verifyAssurances(savedValues, config, expectedParent, keys).error ==
      AssuranceContextError.BackendFailure
  assert hashCalls() == 2
  fail(0)
  assert uint64(verifyAssurances(savedValues, config, expectedParent, keys).value) == 2
  var invalid = savedValues
  invalid[1].signature.bytes[0] = invalid[1].signature.bytes[0] xor 1
  fail(0)
  assert verifyAssurances(invalid, config, expectedParent, keys).error ==
      AssuranceContextError.InvalidSignature
  assert hashCalls() == 2 # Ordinary cryptographic rejection is distinct from backend refusal.
  assert savedValues == values
  # Even refusal/recovery paths must preserve every borrowed key byte.
  for i in 0..<keys.len: assert array[32, byte](keys[i]) == array[32, byte](savedKeys[i])
  clearSeed(seed)

exercise()
# Warmup excludes allocator initialization from this fixed-scope public occupancy observation.
for i in 0..<20: exercise()
let beforeRelease = getOccupiedMem()
# All temporary seed owners release after explicit clearing and fixed transcript/count results need no heap owner.
for i in 0..<1000: exercise()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("assurance_context", 1000, beforeRelease, afterRelease)
echo "ASSURANCE_CONTEXT_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony assurance context: fixed copies, preflight, backend refusal/recovery and scoped release passed"
