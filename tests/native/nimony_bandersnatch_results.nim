# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "failure_driver"}

## Isolated actual/default Bandersnatch result reads protect fixed outputs, sequences and opaque
## owners.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[assertions, cmdline, syncio]
import ../../src/bandersnatch/bandersnatch
import ../support/probe_cases

## Declared misuse modes; custom strings preserve CLI labels and typed dispatch is exhaustive.
# @@ProbeCases
type VerificationProbe = enum
  vpKeyBackend = "key-backend"
  vpKeyShort = "key-short"
  vpKeyZero = "key-zero"
  vpNormalizeShort = "normalize-short"
  vpOutputInvalid = "output-invalid"
  vpProofOwner = "proof-owner"
  vpProofShort = "proof-short"
  vpPublicOwner = "public-owner"
  vpPublicShort = "public-short"
  vpRingOutputOwner = "ring-output-owner"
  vpRootOwner = "root-owner"
  vpRootShort = "root-short"
  vpSetupBackend = "setup-backend"
  vpSetupBounds = "setup-bounds"
  vpSignatureOwner = "signature-owner"
  vpSignatureShort = "signature-short"

# Validate selection or list declarations before reading any runtime fixture.
let selectedProbe = selectProbe[VerificationProbe](paramStr(1))
# Constructor refusal affects only the test observer and never changes production ABI behavior.
proc reset(flags: cint) {.importc: "bo_reset", cdecl.}
let useDefault = paramStr(2) == "default"
let mode = paramStr(1)
reset(0)
case selectedProbe
of vpKeyShort, vpKeyZero, vpKeyBackend:
  var scalar = default(array[32, byte])
  let wanted = if mode == "key-short": BsError.InvalidLength elif mode ==
      "key-zero": BsError.InvalidEncoding else: BsError.BackendFailure
  if mode == "key-backend":
    scalar[0] = 1 # Valid source isolates provider refusal from scalar validation.
    reset(1)
  let failed = if mode == "key-short": importScalar([]) else: importScalar(scalar)
  let parsed = if useDefault: default(BsResult[BsKey]) else: failed
  assert parsed.error == (if useDefault: BsError.Uninitialized else: wanted)
  discard publicKey(parsed.value)
of vpSetupBounds, vpSetupBackend:
  if mode == "setup-backend": reset(2) # A refused setup allocation must publish no owner.
  let failed = newSetup(if mode == "setup-bounds": 0 else: 8)
  let parsed = if useDefault: default(BsResult[BsSetup]) else: failed
  assert parsed.error == (if useDefault: BsError.Uninitialized elif mode ==
      "setup-bounds": BsError.InvalidLength else: BsError.BackendFailure)
  close(parsed.value)
of vpPublicOwner, vpPublicShort:
  let failed = if mode == "public-owner": publicKey(default(BsKey)) else: importPublicKey([])
  let parsed = if useDefault: default(BsResult[BsPublicKey]) else: failed
  assert parsed.error == (if useDefault: BsError.Uninitialized elif mode ==
      "public-owner": BsError.InvalidOwner else: BsError.InvalidLength)
  echo array[32, byte](parsed.value)[0]
of vpSignatureShort, vpSignatureOwner:
  let failed = if mode == "signature-short": importSignature([]) else: sign(default(BsKey), [], [])
  let parsed = if useDefault: default(BsResult[BsSignature]) else: failed
  assert parsed.error == (if useDefault: BsError.Uninitialized elif mode ==
      "signature-short": BsError.InvalidLength else: BsError.InvalidOwner)
  echo array[96, byte](parsed.value)[0]
of vpRootShort, vpRootOwner:
  # This canonical public encoding is the first pinned draft-29 vector's point.
  let public = [0xa1'u8, 0xb1, 0xda, 0x71, 0xcc, 0x46, 0x82, 0xe1, 0x59, 0xb7, 0xda, 0x23, 0x05,
      0x0d, 0x8b, 0x62, 0x61, 0xeb, 0x11, 0xa3, 0x24, 0x7c, 0x89, 0xb0, 0x7e, 0xf5, 0x6c, 0xcd,
      0x00, 0x2f, 0xd3, 0x8b]
  let failed = if mode == "root-short": importRingRoot([]) else: commitRing(default(BsSetup), public)
  let parsed = if useDefault: default(BsResult[BsRingRoot]) else: failed
  assert parsed.error == (if useDefault: BsError.Uninitialized elif mode ==
      "root-short": BsError.InvalidLength else: BsError.InvalidOwner)
  echo array[144, byte](parsed.value)[0]
of vpProofShort, vpProofOwner:
  let public = [0xa1'u8, 0xb1, 0xda, 0x71, 0xcc, 0x46, 0x82, 0xe1, 0x59, 0xb7, 0xda, 0x23, 0x05,
      0x0d, 0x8b, 0x62, 0x61, 0xeb, 0x11, 0xa3, 0x24, 0x7c, 0x89, 0xb0, 0x7e, 0xf5, 0x6c, 0xcd,
      0x00, 0x2f, 0xd3, 0x8b]
  let failed = if mode == "proof-short": importRingProof([]) else: signRing(default(BsSetup),
      default(BsKey), 0, public, [], [])
  let parsed = if useDefault: default(BsResult[BsRingProof]) else: failed
  assert parsed.error == (if useDefault: BsError.Uninitialized elif mode ==
      "proof-short": BsError.InvalidLength else: BsError.InvalidOwner)
  echo array[784, byte](parsed.value)[0]
of vpOutputInvalid, vpRingOutputOwner:
  let failed = if mode == "output-invalid": verify(default(BsPublicKey), default(BsSignature), [], [
      ]) else: verifyRing(default(BsSetup), default(BsRingRoot), default(BsRingProof), [], [])
  let parsed = if useDefault: default(BsResult[BsOutput]) else: failed
  assert parsed.error == (if useDefault: BsError.Uninitialized elif mode ==
      "output-invalid": BsError.InvalidEncoding else: BsError.InvalidOwner)
  echo array[32, byte](parsed.value)[0]
of vpNormalizeShort:
  let failed = normalizeRing([])
  let parsed = if useDefault: default(BsResult[seq[byte]]) else: failed
  assert parsed.error == (if useDefault: BsError.Uninitialized else: BsError.InvalidLength)
  echo parsed.value.len
