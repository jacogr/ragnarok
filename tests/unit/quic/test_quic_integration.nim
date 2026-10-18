# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Enabled CE fixture composition, private snapshot/bank aliases, native refusal and scoped ARC
## release.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import ../../support/arc_evidence
import std/[assertions, envvars, syncio]
import ../../../src/quic/integration
import ../../../src/codec/owned

# Faults affect only this test-linked observer; production hashes still use the maintained primitive ABI.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
# Fail after a completed prefix to verify atomic publication of multi-entry fixture banks.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# Read controlled public fixture bytes; no production protocol parsing occurs here.
proc readBytes(path: string): seq[byte] {.raises.} =
  let text = readFile(path)
  result = newSeq[byte](text.len)
  for i, c in text: result[i] = byte(c) # Own the test input independently of the file string.

# Capture/alias/release a small digest, retaining a codec child after all parent handles leave scope.
proc owners(original: seq[byte]) =
  fail(0)
  let key = preimageKey(original)
  assert key.error == IntegrationError.None
  var input = newSeq[byte](original.len)
  for i, b in original: input[i] = b # Deliberately reusable borrowed receive storage.
  var escaped = default(VerifiedDigest)
  block:
    let checked = captureDigest(input, key.value)
    assert checked.error == IntegrationError.None
    escaped = checked.value
  for b in input: assert b == 0xa5 # Capture actively overwrote every source byte.
  var alias = escaped
  let child = verifiedOwner(alias)
  assert child.error == IntegrationError.None
  var output = newSeq[byte](original.len + 2)
  for i in 0..<output.len: output[i] = 0x55 # Detect prefix-only writes and tail corruption.
  assert copyVerifiedWire(alias, output).value == original.len
  for i, b in original: assert output[i] == b # Exact original bytes survive source overwrite.
  assert output[^1] == 0x55 and output[^2] == 0x55
  output[0] = output[0] xor 1
  var fresh = newSeq[byte](original.len)
  assert copyVerifiedWire(alias, fresh).value == original.len and fresh == original
  var short = @[0x77'u8]
  assert copyVerifiedWire(alias, short).error == IntegrationError.Owner and short == @[0x77'u8]
  escaped = default(VerifiedDigest)
  assert wireLength(alias).value == original.len # A retained alias outlives its source handle.
  alias = default(VerifiedDigest) # The codec child now outlives every integration snapshot handle.
  assert encodeOwned(child.value, fresh).value == original.len and fresh == original
  fail(1)
  for i, b in original: input[i] = b # Backend refusal is a typed failure after capture, not a fabricated owner.
  assert captureDigest(input, key.value).error == IntegrationError.Crypto
  fail(0)
  var wrong = array[32, byte](key.value)
  wrong[0] = wrong[0] xor 1
  assert captureDigest(fresh, PreimageKey(wrong)).error == IntegrationError.HashMismatch
  for i, b in original: fresh[i] = b # Refusal/wrong-key cleanup must permit an immediate healthy retry.
  assert captureDigest(fresh, key.value).error == IntegrationError.None

# Default owners/banks cannot select zero keys or expose mutable backing storage; reload is atomic.
proc banks(directory, alternate: string) =
  fail(0)
  var bank = default(IntegrationBank)
  assert findFixture(bank, default(array[32, byte])) == -1
  assert fixtureKey(bank, 0).error == IntegrationError.Owner
  assert fixtureBytes(bank, 0).error == IntegrationError.Owner
  assert loadBank(bank, directory)
  let alias = bank
  let key = fixtureKey(bank, 0)
  let copied = fixtureBytes(bank, 0)
  assert key.error == IntegrationError.None and copied.error == IntegrationError.None
  var source = copied.value
  source[0] = source[0] xor 1
  assert fixtureBytes(bank, 0).value == copied.value # Extracted copies cannot mutate a retained bank.
  assert findFixture(bank, array[32, byte](key.value)) == 0
  assert findFixture(bank, [0'u8]) == -1
  for index in [-1, 8]:
    # No malformed ordinal may reach the bank's private fixed arrays.
    assert fixtureKey(bank, index).error == IntegrationError.Owner
    assert fixtureBytes(bank, index).error == IntegrationError.Owner
  failAfter(3)
  assert not loadBank(bank, alternate) # A late refusal must not publish the partially hashed candidate.
  fail(0)
  assert fixtureBytes(bank, 0).value == copied.value and fixtureBytes(alias, 0).value == copied.value
  assert not loadBank(bank, directory & "/missing")
  assert array[32, byte](fixtureKey(bank, 0).value) == array[32, byte](
      key.value) # Recoverable file failures preserve the old snapshot too.
  assert loadBank(bank, alternate)
  assert fixtureBytes(bank, 0).value != copied.value # Healthy reload publishes a genuinely different candidate.
  bank = default(IntegrationBank)
  assert fixtureBytes(alias, 0).value == copied.value
  var empty = default(VerifiedDigest)
  var output = @[0x99'u8]
  assert verifiedOwner(empty).error == IntegrationError.Owner
  assert wireLength(empty).error == IntegrationError.Owner
  assert copyVerifiedWire(empty, output).error == IntegrationError.Owner and output == @[0x99'u8]

# Original random-capture selftest and warmed owner scopes use the real linked crypto implementation.
proc main() {.raises.} =
  let args = @[getEnv("RAGNAROK_TEST_WIRES"), getEnv("RAGNAROK_TEST_RELOAD")]
  assert args[0].len > 0 and args[1].len > 0, "missing prepared native fixtures"
  let original = readBytes(args[0] & "/0.bin")
  integrationSelfTest()
  banks(args[0], args[1])
  for i in 0..<20: owners(original) # Warm exactly the measured small-snapshot workload.
  let before = getOccupiedMem()
  for i in 0..<1000: owners(original) # All source, child, parent, failure and output allocations retire.
  let after = getOccupiedMem()
  assert before == after
  # Preserve fresh numeric observations independently of portable expected output.
  recordArcRelease("quic_integration", 1000, before, after)
  echo "INTEGRATION_ARC_RELEASE cycles=1000 unchanged"
  echo "Nimony integration: capture/copy/alias, immutable banks and refusal recovery passed"

# Trusted fixture I/O failures are not successful protocol verdicts.
try:
  main()
except:
  quit(2)
