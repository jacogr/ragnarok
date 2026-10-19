# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native guarantee owner, late-failure, alias and default-result safety checks.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

## Verification: {"arc": "guarantee_arc_release"}

import ../../support/arc_evidence
import std/[assertions, envvars, syncio]
import ../../../src/codec/[guarantees, report_owned, owned, bounded, assurances]

# Copy a fixture file into explicit owned octets without type-punning a mutable string.
proc bytes(path: string): seq[byte] {.raises.} =
  let text = readFile(path)
  result = newSeq[byte](text.len)
  # Every byte belongs to this test input and can safely be mutated after capture.
  for i in 0..<text.len: result[i] = byte(text[i])

let limits = GuaranteeConfig(cores: CoreCount(341), validators: ValidatorCount(1023),
    maxBytes: ByteLimit(1048576))
var wire: seq[byte] = @[]
# Fixture I/O is trusted test setup and must fail explicitly if unavailable.
try:
  wire = bytes(getEnv("RAGNAROK_GUARANTEE_FIXTURE"))
except:
  # A missing fixture cannot count as successful codec coverage.
  quit 2
let first = decodeOwnedReport(wire, 341)
assert first.error == OwnershipError.None
# The authored fixture has no prerequisites and a one-byte core at the known C.2 offset.
assert wire[272] == 0 and wire[273] == 0
wire[273] = 1
let second = decodeOwnedReport(wire, 341)
assert second.error == OwnershipError.None
var values: array[8, Guarantee] = default(array[8, Guarantee])
# Two strictly increasing cores create a valid composed source with later-record failure opportunities.
for i in 0..<2:
  values[i] = Guarantee(report: if i == 0: first.value else: second.value,
    slot: GuaranteeSlot(uint32(i+1)), credentialCount: 2)
  values[i].credentials[0].validator = GuarantorIndex(0)
  values[i].credentials[1].validator = GuarantorIndex(1)
var output: array[4096, byte] = default(array[4096, byte])
let encoded = encodeGuarantees(values.toOpenArray(0, 1), limits, output)
assert encoded.error == GuaranteeError.None
let captured = decodeGuarantees(output.toOpenArray(0, encoded.value-1), limits)
assert captured.error == GuaranteeError.None and captured.value.count == 2
# Caller source mutations cannot change retained report bytes or fixed credential metadata.
for i in 0..<wire.len: wire[i] = 0
let selected = guaranteeAt(captured.value.owner, 1)
assert selected.error == GuaranteeError.None and uint32(selected.value.slot) == 2
var copy = selected.value
copy.credentials[1].validator = GuarantorIndex(0)
assert uint16(guaranteeAt(captured.value.owner, 1).value.credentials[1].validator) == 1
# A default owner is a failure, distinct from a validated empty sequence.
var absent: OwnedGuarantees = default(OwnedGuarantees)
assert guaranteeAt(absent, 0).error == GuaranteeError.InvalidOwner
assert encodeOwnedGuarantees(absent, output).error == GuaranteeError.InvalidOwner
var badReport: OwnedReport = default(OwnedReport)
assert ownedReportOverlapsOutput(badReport, output).error == OwnershipError.InvalidOwner
assert not ownedReportOverlapsOutput(first.value, output).value
# A final invalid credential must be detected before any earlier source record writes its output.
values[1].credentials[1].validator = GuarantorIndex(1023)
for i in 0..<output.len: output[i] = 0xA5
let failed = encodeGuarantees(values.toOpenArray(0, 1), limits, output)
assert failed.error == GuaranteeError.InvalidValidator
for value in output: assert value == 0xA5 # Whole destination remains unchanged.
values[1].credentials[1].validator = GuarantorIndex(1)
# The backing array has enough real bytes for this alias fixture's full output extent.
assert encoded.value <= sizeof(values)
let alias = cast[ptr array[sizeof(values), byte]](addr values[0])
assert encodeGuarantees(values.toOpenArray(0, 1), limits,
  alias[].toOpenArray(0, encoded.value-1)).error == GuaranteeError.AliasedBuffers
# Invalid-result access is verified in independent subprocesses; Nimony contracts are fail-stop.
assert decodeGuarantees(@[255'u8], limits).error == GuaranteeError.Truncated
# Empty sequences capture a real owner and canonical one-byte count.
var empty: array[1, byte] = default(array[1, byte])
let decodedEmpty = decodeGuarantees(empty, limits)
assert decodedEmpty.error == GuaranteeError.None and decodedEmpty.value.count == 0

# Capture a local complete parent whose child identity differs without changing report size.
proc captureParent(marker: byte): OwnedGuarantees =
  var reportWire = newSeq[byte](ownedReportInfo(first.value).value.consumed)
  assert encodeOwnedReport(first.value, reportWire).error == OwnershipError.None
  reportWire[0] = marker
  let child = decodeOwnedReport(reportWire, 341)
  assert child.error == OwnershipError.None
  var records = default(array[1, Guarantee])
  records[0] = Guarantee(report: child.value, slot: GuaranteeSlot(uint32(marker)),
      credentialCount: 2)
  records[0].credentials[1].validator = GuarantorIndex(1)
  var localWire = default(array[4096, byte])
  let encoded = encodeGuarantees(records, limits, localWire)
  assert encoded.error == GuaranteeError.None
  let captured = decodeGuarantees(localWire.toOpenArray(0, encoded.value-1), limits)
  assert captured.error == GuaranteeError.None
  # Destroy all original typed/wire sources before returning the independent retained parent.
  records[0] = default(Guarantee)
  reportWire[0] = marker xor 255
  localWire[1] = marker xor 255
  captured.value.owner

# Replacement releases one handle while an alias and a returned child retain their original data.
proc escapedChild(marker: byte): Guarantee =
  var parent = captureParent(marker)
  let retained = parent
  parent = captureParent(marker xor 255)
  assert ownedReportInfo(guaranteeAt(parent, 0).value.report).value.header.packageHash.bytes[0] == (marker xor 255)
  let child = guaranteeAt(retained, 0)
  assert child.error == GuaranteeError.None and uint32(child.value.slot) == uint32(marker)
  child.value

# Last-parent release must leave the escaped child alive until the end of this isolated cycle.
proc releaseCycle(marker: byte) =
  let child = escapedChild(marker)
  assert ownedReportInfo(child.report).value.header.packageHash.bytes[0] == marker
  var copied = default(array[4096, byte])
  assert encodeOwnedReport(child.report, copied).error == OwnershipError.None
  assert copied[0] == marker

# Warm up public allocator accounting before measuring isolated parent/child ARC scopes.
for i in 0..<100: releaseCycle(byte(i mod 256))
let beforeRelease = getOccupiedMem()
# Each return releases all temporary parents, aliases, child handles, buffers and source records.
for i in 0..<1000: releaseCycle(byte(i mod 256))
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
let missingResult = default(GuaranteeResult[GuaranteesRead])
assert missingResult.error == GuaranteeError.Uninitialized
# Preserve raw measurements outside the platform-independent completion output.
recordArcRelease("guarantees", 1000, beforeRelease, afterRelease)
echo "GUARANTEE_ARC_RELEASE cycles=1000 unchanged"
echo "Guarantees: retained parents/children, late failures, aliases, defaults and ARC release passed"
