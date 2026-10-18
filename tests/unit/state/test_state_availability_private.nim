# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Project-only retained child/report, immutable copy and arithmetic checks using public
## allocator observations.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import ../../support/arc_evidence
import std/[assertions, envvars, syncio]
import ../../../src/codec/[report_owned, owned]
include ../../../src/codec/state_availability
var fixture: seq[byte] = @[]
# Fixture I/O is trusted setup; unavailable input cannot count as coverage.
try:
  assert getEnv("RAGNAROK_STATE_REPORT").len > 0, "missing independent report fixture"
  let text = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  fixture = newSeq[byte](text.len)
  # Copy explicit octets rather than relying on string/sequence layouts.
  for i in 0..<text.len: fixture[i] = byte(text[i])
except:
  # No codec run is valid without its independently authored report fixture.
  quit 2

## Explicit tiny structural chain and independent child/parent budgets.
proc policy(): AvailabilityConfig =
  AvailabilityConfig(guarantee: GuaranteeConfig(cores: CoreCount(2), validators: ValidatorCount(6),
    maxBytes: ByteLimit(2000000)), maxPresent: ElementLimit(2), maxBytes: ByteLimit(4000000))

## Capture report bytes independently and author full guarantee fields before parent encoding.
proc source(marker: uint32, fixture: openArray[byte]): seq[AvailabilityAssignment] =
  let report = decodeOwnedReport(fixture, 2)
  assert report.error == OwnershipError.None
  var child = Guarantee(report: report.value, slot: GuaranteeSlot(marker), credentialCount: 2)
  child.credentials[1].validator = GuarantorIndex(1)
  child.credentials[0].signature = default(GuaranteeSignature)
  @[presentAssignment(child, AssignmentSlot(0x01020000+marker)), absentAssignment()]

## Return an immutable parent after local report sources, child fields, entry and mutable wire retire.
proc escaped(marker: uint32, fixture: openArray[byte]): AvailabilitySnapshot =
  var original = source(marker, fixture)
  let entry = availabilityStateEntry(original, policy())
  assert entry.error == AvailabilityError.None
  var wire = entry.value.value
  let parsed = decodeAvailabilityState(wire, policy())
  assert parsed.error == AvailabilityError.None
  result = parsed.value.snapshot
  original = @[]
  # All observed child bytes must remain independent of the destroyed parent input.
  for i in 0..<wire.len: wire[i] = 0

## Keep only a copied assignment after its callee-local parent loses its final reference.
proc escapedChild(fixture: openArray[byte]): AvailabilityAssignment =
  let owner = escaped(61, fixture)
  availabilityAt(owner, AssignmentCoreIndex(0)).value

## Each scope releases replaced parents, retained assignment/report children and failed preflight temporaries.
proc cycle(fixture: openArray[byte]) =
  var owner = escaped(17, fixture)
  let alias = owner
  owner = escaped(29, fixture)
  assert uint32(availabilityAt(alias, AssignmentCoreIndex(0)).value.guarantee.slot) == 17
  assert uint32(availabilityAt(owner, AssignmentCoreIndex(0)).value.registered) == 0x0102001d
  var info = availabilityInfo(alias).value
  info.cores = 0
  info.present = 0
  assert availabilityInfo(alias).value.present == 1
  var item = availabilityAt(alias, AssignmentCoreIndex(0)).value
  var copied = item.guarantee
  copied.slot = GuaranteeSlot(0)
  copied.credentials[0].validator = GuarantorIndex(5)
  item = presentAssignment(copied, AssignmentSlot(0))
  assert uint16(availabilityAt(alias, AssignmentCoreIndex(0)).value.guarantee.credentials[
      0].validator) == 0
  item = absentAssignment()
  assert availabilityAt(alias, AssignmentCoreIndex(0)).value.present
  assert not availabilityAt(alias, AssignmentCoreIndex(1)).value.present
  owner = default(AvailabilitySnapshot)
  assert availabilityInfo(owner).error == AvailabilityError.InvalidOwner
  assert availabilityInfo(alias).value.cores == 2
  assert availabilityAt(alias, AssignmentCoreIndex(high(uint64))).error ==
      AvailabilityError.InvalidIndex
  let child = escapedChild(fixture)
  assert uint32(child.guarantee.slot) == 61
  assert ownedReportInfo(child.guarantee.report).error == OwnershipError.None
  var replay = newSeq[byte](fixture.len)
  assert encodeOwnedReport(child.guarantee.report, replay).error == OwnershipError.None
  assert replay == fixture
  let original = source(43, fixture)
  var wire = availabilityStateEntry(original, policy()).value.value
  wire[wire.len-1] = 2
  let before = getOccupiedMem()
  assert decodeAvailabilityState(wire, policy()).error == AvailabilityError.InvalidTag
  assert before == getOccupiedMem()
  assert decodeAvailabilityState(wire.toOpenArray(0, wire.len-2), policy()).error ==
      AvailabilityError.Truncated
  let empty = decodeAvailabilityState([0'u8, 0], policy()).value.snapshot
  assert availabilityInfo(empty).value.present == 0

# Trusted nonnegative additions still need explicit overflow and byte-policy checks under wrapping arithmetic.
var cursor = high(int)-4
assert grow(cursor, 4, ByteLimit(high(uint64))) == AvailabilityError.None
assert cursor == high(int)
assert grow(cursor, 1, ByteLimit(high(uint64))) == AvailabilityError.LengthOverflow
assert cursor == high(int)
assert grow(cursor, 0, ByteLimit(high(uint64))) == AvailabilityError.None
cursor = high(int)-3
assert grow(cursor, 4, ByteLimit(high(uint64))) == AvailabilityError.LengthOverflow
assert cursor == high(int)-3
cursor = 0
assert grow(cursor, high(int), ByteLimit(high(uint64))) == AvailabilityError.None
assert cursor == high(int)
cursor = 0
assert grow(cursor, 4, ByteLimit(3)) == AvailabilityError.LimitExceeded
# Warm up report capture and allocator bookkeeping before the isolated live-occupancy comparison.
for i in 0..<100: cycle(fixture)
let beforeRelease = getOccupiedMem()
# Every scope retires the final child report owner as well as parent and copied credential temporaries.
for i in 0..<1000: cycle(fixture)
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("state_availability_private", 1000, beforeRelease, afterRelease)
echo "AVAILABILITY_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony chapter 10: escaped/replaced parents, independent assignments, retained reports and scoped ARC release passed"
