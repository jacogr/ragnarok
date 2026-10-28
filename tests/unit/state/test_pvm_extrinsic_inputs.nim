# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_extrinsic_inputs_arc_release"}

## Independent commitments, ordered geometry, immutable ownership, exact policies and ARC release.

import std/assertions
import std/syncio
import ../../../src/pvm/host_fetch as pvm_host_fetch
import ../../../src/state/extrinsic_inputs as state_extrinsic_inputs
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/work_package as codec_work_package
import ../../support/pvm_extrinsic_inputs
import ../../support/testing_arc_evidence

proc input(verified: VerifiedExtrinsics, item, index: uint64): ExtrinsicInputsResult[seq[byte]] =
  ## Keep full-width boundary fixtures concise while exercising the public nominal index domains.
  verified.extrinsicInput(FetchItemIndex(item), ExtrinsicInputIndex(index))

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset observer counters and select a controlled backend refusal.
proc refuseAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse after a successful prefix without changing production hashing.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe exact calls so preflight ordering has independent evidence.

proc expect[T](outcome: ExtrinsicInputsResult[T], reason: ExtrinsicInputsError) =
  ## Check reasons without extracting refused alternatives or creating long formatter-sensitive comparisons.
  assert outcome.error == reason
let abc = @[97'u8, 98, 99]
let abd = @[97'u8, 98, 100]
let empty = newSeq[byte](0)
let manifest = extrinsicPackage([@[AbcExtrinsic, EmptyExtrinsic, AbcExtrinsic], @[], @[AbdExtrinsic]])
var rows = @[@[abc, empty, abc], newSeq[seq[byte]](0), @[abd]]
let complete = verifyExtrinsicInputs(manifest, rows, extrinsicLimits()).value
let info = complete.extrinsicInputsInfo.value
assert info.items == 3 and info.entries == 4
assert info.payloadBytes == 9 and info.hashBytes == 9
assert complete.input(0, 0).value == abc
assert complete.input(0, 1).value == empty
assert complete.input(0, 2).value == abc
assert complete.input(2, 0).value == abd
assert complete.extrinsicInputsPackage.value.workPackageInfo.value.items == 3
# Every entry counts, including empty preimages and repeated commitments; independently exhaust each local cap.
var exact = ExtrinsicInputsLimits(entries: ElementLimit(4), payloadBytes: ByteLimit(9),
    hashBytes: ByteLimit(9))
expect(verifyExtrinsicInputs(manifest, rows, exact), ExtrinsicInputsError.None)
exact.entries = ElementLimit(3)
expect(verifyExtrinsicInputs(manifest, rows, exact), ExtrinsicInputsError.LimitExceeded)
exact.entries = ElementLimit(4)
exact.payloadBytes = ByteLimit(8)
expect(verifyExtrinsicInputs(manifest, rows, exact), ExtrinsicInputsError.LimitExceeded)
exact.payloadBytes = ByteLimit(9)
exact.hashBytes = ByteLimit(8)
expect(verifyExtrinsicInputs(manifest, rows, exact), ExtrinsicInputsError.LimitExceeded)
# Reject absent/extra/reordered rows and occurrences without silently dropping an authenticated prefix.
expect(verifyExtrinsicInputs(manifest, [], extrinsicLimits()), ExtrinsicInputsError.InvalidShape)
let missing = @[@[abc, empty], newSeq[seq[byte]](0), @[abd]]
expect(verifyExtrinsicInputs(manifest, missing, extrinsicLimits()),
    ExtrinsicInputsError.InvalidShape)
let extra = @[@[abc, empty, abc, abc], newSeq[seq[byte]](0), @[abd]]
expect(verifyExtrinsicInputs(manifest, extra, extrinsicLimits()), ExtrinsicInputsError.InvalidShape)
let reordered = @[@[abc, empty, abc], @[abd], newSeq[seq[byte]](0)]
expect(verifyExtrinsicInputs(manifest, reordered, extrinsicLimits()),
    ExtrinsicInputsError.InvalidShape)
let short = @[@[abc, @[97'u8], abc], newSeq[seq[byte]](0), @[abd]]
expect(verifyExtrinsicInputs(manifest, short, default(ExtrinsicInputsLimits)),
    ExtrinsicInputsError.LengthMismatch)
let changed = @[@[abc, empty, abc], newSeq[seq[byte]](0), @[abc]]
expect(verifyExtrinsicInputs(manifest, changed, extrinsicLimits()),
    ExtrinsicInputsError.HashMismatch)
expect(verifyExtrinsicInputs(manifest, changed, default(ExtrinsicInputsLimits)),
    ExtrinsicInputsError.LimitExceeded)
let ordered = extrinsicPackage([@[AbcExtrinsic, AbdExtrinsic]])
expect(verifyExtrinsicInputs(ordered, [@[abd, abc]], extrinsicLimits()),
    ExtrinsicInputsError.HashMismatch)
var wrongHash = EmptyExtrinsic
wrongHash.hash = ExtrinsicHash(default(array[32, byte]))
expect(verifyExtrinsicInputs(extrinsicPackage([@[wrongHash]]), [@[empty]], extrinsicLimits()),
    ExtrinsicInputsError.HashMismatch)
# All-empty item rows and authentic empty preimages remain real successful selections even with zero byte caps.
let noInputs = extrinsicPackage([newSeq[ExtrinsicCommitment](0)])
let noRows = [newSeq[seq[byte]](0)]
expect(verifyExtrinsicInputs(noInputs, noRows, default(ExtrinsicInputsLimits)),
    ExtrinsicInputsError.None)
let emptyOnly = extrinsicPackage([@[EmptyExtrinsic]])
let emptyLimits = ExtrinsicInputsLimits(entries: ElementLimit(1))
expect(verifyExtrinsicInputs(emptyOnly, [@[empty]], emptyLimits), ExtrinsicInputsError.None)
expect(verifyExtrinsicInputs(emptyOnly, [@[empty]], default(ExtrinsicInputsLimits)),
    ExtrinsicInputsError.LimitExceeded)
# Exercise the protocol occurrence and item ceilings with empty inputs so byte caps cannot hide count errors.
var maximumCommitments = newSeq[ExtrinsicCommitment](128)
var maximumRows = newSeq[seq[byte]](128)
for index in 0..<128: maximumCommitments[index] = EmptyExtrinsic
let maximumPackage = extrinsicPackage([maximumCommitments])
let maximumLimits = ExtrinsicInputsLimits(entries: ElementLimit(128))
let maximum = verifyExtrinsicInputs(maximumPackage, [maximumRows], maximumLimits).value
assert maximum.extrinsicInputsInfo.value.entries == 128
var sixteen = newSeq[seq[ExtrinsicCommitment]](16)
let sixteenPackage = extrinsicPackage(sixteen)
let sixteenInputs = newSeq[seq[seq[byte]]](16)
expect(verifyExtrinsicInputs(sixteenPackage, sixteenInputs, default(ExtrinsicInputsLimits)),
    ExtrinsicInputsError.None)
# Full-width access checks precede narrowing, including an existing empty row.
for item in [3'u64, high(uint64)]:
  expect(complete.input(item, 0), ExtrinsicInputsError.InvalidIndex)
for index in [3'u64, high(uint64)]:
  expect(complete.input(0, index), ExtrinsicInputsError.InvalidIndex)
expect(complete.input(1, 0), ExtrinsicInputsError.InvalidIndex)
expect(default(VerifiedExtrinsics).extrinsicInputsInfo, ExtrinsicInputsError.Uninitialized)
expect(default(VerifiedExtrinsics).extrinsicInputsPackage, ExtrinsicInputsError.Uninitialized)
expect(default(VerifiedExtrinsics).input(0, 0), ExtrinsicInputsError.Uninitialized)
expect(verifyExtrinsicInputs(default(OwnedWorkPackage), rows, extrinsicLimits()),
    ExtrinsicInputsError.InvalidPackage)
# Fault every backend position and prove preflight checks never invoke hashing.
for prefix in 0..<4:
  refuseAfter(cint(prefix))
  expect(verifyExtrinsicInputs(manifest, rows, extrinsicLimits()),
      ExtrinsicInputsError.BackendFailure)
  assert hashes() == cint(prefix+1)
reset(0)
expect(verifyExtrinsicInputs(manifest, rows, exact), ExtrinsicInputsError.LimitExceeded)
assert hashes() == 0
expect(verifyExtrinsicInputs(manifest, short, extrinsicLimits()),
    ExtrinsicInputsError.LengthMismatch)
assert hashes() == 0
expect(verifyExtrinsicInputs(manifest, missing, extrinsicLimits()),
    ExtrinsicInputsError.InvalidShape)
assert hashes() == 0
expect(verifyExtrinsicInputs(manifest, rows, extrinsicLimits()), ExtrinsicInputsError.None)
assert hashes() == 4
reset(0)
# Deep-copy every level and retain the original package rather than a replaceable detached manifest.
rows[0][0][0] = 255
rows[0][2] = @[0'u8]
rows[2] = @[]
assert complete.input(0, 0).value == abc
assert complete.input(0, 2).value == abc
assert complete.input(2, 0).value == abd
var extracted = complete.input(0, 0).value
extracted[0] = 255
var copiedInfo = complete.extrinsicInputsInfo.value
copiedInfo.entries = 0
assert complete.input(0, 0).value == abc
assert complete.extrinsicInputsInfo.value.entries == 4
let retainedHash = complete.extrinsicInputsPackage.value.workItemAt(2).value.extrinsicAt(0).value.hash
assert array[32, byte](retainedHash) == array[32, byte](AbdExtrinsic.hash)
proc detached(): VerifiedExtrinsics =
  ## Retire all original tables and package temporaries before exercising retained extraction.
  verifyExtrinsicInputs(extrinsicPackage([@[AbcExtrinsic]]), [@[@[97'u8, 98, 99]]], extrinsicLimits()).value
assert detached().input(0, 0).value == abc
proc cycle() =
  ## Release owned bytes, copied bytes and a late refused candidate on every iteration.
  let done = detached()
  assert done.input(0, 0).value == abc
  expect(verifyExtrinsicInputs(manifest, changed, extrinsicLimits()),
      ExtrinsicInputsError.HashMismatch)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_extrinsic_inputs", 1000, before, after)
echo "PVM extrinsic inputs passed"
echo "ARC_RELEASE cycles=1000 unchanged"
