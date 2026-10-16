## Retained full-guarantee/report lifetimes, optional fields, independent slots and failure/index guards.
import std/os
import ../../src/codec/[state_availability, guarantees, report_owned, owned, bounded, assurances]

## Failed/default results cannot expose a fabricated owner or progress under optimized builds.
proc guarded[T](parsed: AvailabilityResult[T]) =
  var caught = false
  try:
    discard parsed.value # No default success value on failure.
  except FieldDefect:
    caught = true # Retain checked variant fields under ARC/Clang LTO.
  doAssert caught

## An absent assignment has no registration timestamp or default guarantee.
proc absentGuard(value: AvailabilityAssignment) =
  var caught = false
  try:
    discard value.registered # Presence must be selected before reading either child field.
  except FieldDefect:
    caught = true # Absence is not registration zero.
  doAssert caught

## Return a copied child after the temporary parent and all its handles leave scope.
proc detachedChild(input: openArray[byte], config: AvailabilityConfig): AvailabilityAssignment =
  let parsed = decodeAvailabilityState(input, config)
  doAssert parsed.error == AvailabilityError.None
  let item = availabilityAt(parsed.value.snapshot, AssignmentCoreIndex(0))
  doAssert item.error == AvailabilityError.None
  item.value

## Capture independent report fixtures and retain a child after all parent/source handles are replaced.
proc main() =
  let config = AvailabilityConfig(guarantee: GuaranteeConfig(cores: CoreCount(2),
      validators: ValidatorCount(6),
    maxBytes: ByteLimit(2_000_000)), maxPresent: ElementLimit(2), maxBytes: ByteLimit(4_000_000))
  let raw = readFile(paramStr(1))
  var reportWire = newSeq[byte](raw.len)
  for i in 0..<raw.len: reportWire[i] = byte(raw[i]) # Fixture is independently encoded by the Python reference.
  let report = decodeOwnedReport(reportWire, 2)
  doAssert report.error == OwnershipError.None
  var guarantee = Guarantee(report: report.value, slot: GuaranteeSlot(255), credentialCount: 2)
  guarantee.credentials[1].validator = GuarantorIndex(1)
  var values = @[AvailabilityAssignment(present: true, guarantee: guarantee,
      registered: AssignmentSlot(0x01020304)),
    AvailabilityAssignment(present: false)]
  let encoded = availabilityStateEntry(values, config)
  doAssert encoded.error == AvailabilityError.None and array[31, byte](encoded.value.key)[0] == 10
  let standalone = encodeGuaranteeValue(guarantee, config.guarantee)
  doAssert standalone.error == GuaranteeError.None
  let inspected = inspectGuarantee(standalone.value, config.guarantee)
  doAssert inspected.error == GuaranteeError.None and inspected.value.consumed ==
      standalone.value.len
  var wire = encoded.value.value
  let decoded = decodeAvailabilityState(wire, config)
  doAssert decoded.error == AvailabilityError.None
  var parent = decoded.value.snapshot
  let detached = detachedChild(wire, config)
  let copied = availabilityAt(parent, AssignmentCoreIndex(0))
  doAssert copied.error == AvailabilityError.None and copied.value.present
  values[0].guarantee.credentials[0].validator = GuarantorIndex(5)
  parent = default(AvailabilitySnapshot)
  # Destroy original caller report and parent bytes before observing the copied retained child.
  for i in 0..<wire.len: wire[i] = 0
  for i in 0..<reportWire.len: reportWire[i] = 0
  doAssert uint32(copied.value.registered) == 0x01020304 and uint32(copied.value.guarantee.slot) == 255
  doAssert uint16(copied.value.guarantee.credentials[0].validator) == 0
  doAssert ownedReportInfo(copied.value.guarantee.report).error == OwnershipError.None
  var replay = newSeq[byte](raw.len)
  doAssert encodeOwnedReport(copied.value.guarantee.report, replay).error == OwnershipError.None
  # Compare copied octets without relying on any sequence/string memory layout.
  for i in 0..<raw.len: doAssert replay[i] == byte(raw[i])
  doAssert ownedReportInfo(detached.guarantee.report).error == OwnershipError.None
  let info = availabilityInfo(decoded.value.snapshot)
  doAssert info.error == AvailabilityError.None and info.value.cores == 2 and info.value.present == 1
  let absent = availabilityAt(decoded.value.snapshot, AssignmentCoreIndex(1))
  doAssert absent.error == AvailabilityError.None and not absent.value.present
  absentGuard(absent.value)
  guarded(availabilityInfo(parent))
  guarded(availabilityAt(parent, AssignmentCoreIndex(0)))
  let invalid = availabilityAt(decoded.value.snapshot, AssignmentCoreIndex(high(uint64)))
  doAssert invalid.error == AvailabilityError.InvalidIndex
  guarded(invalid)
  guarded(default(AvailabilityResult[AvailabilityRead]))
  let short = decodeAvailabilityState(encoded.value.value.toOpenArray(0, encoded.value.value.len-2), config)
  doAssert short.error == AvailabilityError.Truncated
  guarded(short)
  let empty = availabilityStateEntry([AvailabilityAssignment(present: false),
      AvailabilityAssignment(present: false)], config)
  doAssert empty.error == AvailabilityError.None and empty.value.value == @[0'u8, 0]
  echo "PASS availability state: retained reports/guarantees, optional fields, independent timestamps and result/index guards"

main()
