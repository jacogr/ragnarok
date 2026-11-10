# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_work_signer_arc_release"}

## Actual maintained TLS fixture keys load only into matching opaque owners; malformed/ambiguous input never publishes a signer.

import std/[assertions, envvars, syncio, posix/posix]
import ../../../src/jamnp-s/work_signer
import ../../../src/crypto/primitives
import ../../../src/quic/transport
import ../../../src/codec/bounded
import ../../../src/codec/state/safrole
import ../../../src/lib/atomic/file
import ../../support/[arc_evidence, jamnp_guarantee_fixture]

proc cycle(cert, key: string, expected: StateEdKey, fixture: GuaranteeFixture) =
  ## Successful private imports and identity-mismatch refusals release every seed owner and backend scratch object.
  let imported = loadWorkSigner(cert, key)
  assert imported.error == WorkSignerError.None
  assert array[32, byte](imported.value.signerIdentity.value) == array[32, byte](expected)
  let wrong = loadWorkSigner(cert, getEnv("RAGNAROK_TEST_KEY_B"))
  assert wrong.error == WorkSignerError.IdentityMismatch
  fixture.guaranteeCycle(imported.value)

proc main() {.raises.} =
  ## All key mutation fixtures are generated test-only bytes, never user credential material or printed secrets.
  let cert = getEnv("RAGNAROK_TEST_CERT")
  let key = getEnv("RAGNAROK_TEST_KEY")
  let public = readFile(getEnv("RAGNAROK_TEST_PEER_A"))
  assert public.len == 32
  var expectedBytes = default(array[32, byte])
  for index in 0..<32: expectedBytes[index] = byte(public[index])
  let expected = StateEdKey(expectedBytes)
  assert default(WorkSigner).signerIdentity.error == WorkSignerError.Uninitialized
  assert loadWorkSigner("", key).error == WorkSignerError.InvalidPath
  assert loadWorkSigner(cert, "embedded\0key").error == WorkSignerError.InvalidPath
  let tooLong = newString(4097)
  assert loadWorkSigner(cert, tooLong).error == WorkSignerError.InvalidPath
  assert loadWorkSigner("missing-work-certificate.pem", key).error ==
      WorkSignerError.CertificateFailure
  let absent = loadWorkSigner(cert, "missing-work-private-key.pem")
  assert absent.error == WorkSignerError.ReadFailure
  assert absent.readError == AtomicFileError.IoFailure
  assert loadWorkSigner(cert, ".").error == WorkSignerError.ReadFailure
  var source = default(array[65537, byte])
  defer: clearSecret(source)
  let read = readFileInto(key, source)
  assert read.error == AtomicFileError.None and read.value > 0 and read.value <= 65536
  var path = "work-signer-fixture.pem"
  defer: discard posix.unlink(path.toCString())
  assert replaceAtomicFile(path, [], ByteLimit(65537)) == AtomicFileError.None
  assert loadWorkSigner(cert, path).error == WorkSignerError.KeyFailure
  assert replaceAtomicFile(path, [byte('x')], ByteLimit(65537)) == AtomicFileError.None
  var exact = default(array[1, byte])
  assert readFileInto(path, exact).error == AtomicFileError.LimitExceeded
  var enough = default(array[2, byte])
  let counted = readFileInto(path, enough)
  assert counted.error == AtomicFileError.None and counted.value == 1
  assert enough[0] == byte('x')
  assert loadWorkSigner(cert, path).error == WorkSignerError.KeyFailure
  var scratch = default(array[32, byte])
  for index in 0..<scratch.len: scratch[index] = 165
  assert parseIdentitySeed(addr enough[0], 1, addr scratch[0]) == 0
  for index in 0..<scratch.len: assert scratch[index] ==
      165 # Native refusal must not publish even a partial private seed.
  clearSecret(scratch)
  var fixture = newSeq[byte](read.value+1)
  defer: clearSecret(fixture)
  for index in 0..<read.value: fixture[index] = source[index]
  fixture[fixture.high] = byte('x')
  assert replaceAtomicFile(path, fixture, ByteLimit(65537)) == AtomicFileError.None
  assert loadWorkSigner(cert, path).error == WorkSignerError.KeyFailure
  fixture[fixture.high] = byte('\n')
  assert replaceAtomicFile(path, fixture, ByteLimit(65537)) == AtomicFileError.None
  assert loadWorkSigner(cert, path).error == WorkSignerError.None
  var duplicate = newSeq[byte](read.value*2)
  defer: clearSecret(duplicate)
  for index in 0..<read.value:
    # A second fully valid private key is still an ambiguous input, even if its public identity would match.
    duplicate[index] = source[index]
    duplicate[read.value+index] = source[index]
  for index in 0..<scratch.len: scratch[index] = 165
  assert parseIdentitySeed(addr duplicate[0], csize_t(duplicate.len), addr scratch[0]) == 0
  for index in 0..<scratch.len: assert scratch[index] ==
      165 # A fully parsed first key cannot leak seed output when a later suffix invalidates the file.
  clearSecret(scratch)
  assert replaceAtomicFile(path, duplicate, ByteLimit(65537)) == AtomicFileError.None
  assert loadWorkSigner(cert, path).error == WorkSignerError.KeyFailure
  assert read.value <= 4096
  let malformedBegin = "-----BEGIN PRIVATE KEY-----x\n"
  var prefixed = newSeq[byte](malformedBegin.len+read.value)
  defer: clearSecret(prefixed)
  for index in 0..<malformedBegin.len: prefixed[index] = byte(malformedBegin[index])
  for index in 0..<read.value: prefixed[malformedBegin.len+index] = source[index]
  assert replaceAtomicFile(path, prefixed, ByteLimit(65537)) == AtomicFileError.None
  assert loadWorkSigner(cert, path).error == WorkSignerError.KeyFailure
  let encrypted = "-----BEGIN ENCRYPTED PRIVATE KEY-----\nAAAA\n-----END ENCRYPTED PRIVATE KEY-----\n"
  var encryptedBytes = newSeq[byte](encrypted.len)
  for index in 0..<encrypted.len: encryptedBytes[index] = byte(encrypted[index])
  assert replaceAtomicFile(path, encryptedBytes, ByteLimit(65537)) == AtomicFileError.None
  assert loadWorkSigner(cert, path).error == WorkSignerError.KeyFailure
  var oversized = newSeq[byte](65537)
  defer: clearSecret(oversized)
  assert replaceAtomicFile(path, oversized, ByteLimit(65537)) == AtomicFileError.None
  let refused = loadWorkSigner(cert, path)
  assert refused.error == WorkSignerError.ReadFailure
  assert refused.readError == AtomicFileError.LimitExceeded
  let reporting = guaranteeFixture(expected)
  let otherSigner = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"))
  assert otherSigner.error == WorkSignerError.None
  guaranteeBoundaries(reporting, loadWorkSigner(cert, key).value, otherSigner.value)
  cycle(cert, key, expected, reporting)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(cert, key, expected, reporting)
  let after = getOccupiedMem()
  assert before == after, "private signer imports and mismatch refusals release all owners"
  recordArcRelease("jamnp_work_signer", 1000, before, after)
  echo "JAMNP-S private TLS-matched work signer passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main()
except:
  quit 2 # Setup exceptions cannot stand in for matched private ownership and complete native boundary witnesses.
