## Retained full-guarantee/report lifetimes, optional fields, independent slots and failure/index guards.
import std/[assertions, cmdline, syncio]
import ../../src/codec/[state_availability, guarantees, report_owned, owned, bounded, assurances]

## Return a copied child after the temporary parent and all its handles leave scope.
proc detachedChild(input: openArray[byte], config: AvailabilityConfig): AvailabilityAssignment =
  let parsed = decodeAvailabilityState(input, config)
  assert parsed.error == AvailabilityError.None
  let item = availabilityAt(parsed.value.snapshot, AssignmentCoreIndex(0))
  assert item.error == AvailabilityError.None
  item.value

## Capture independent report fixtures and retain a child after all parent/source handles are replaced.
proc main() {.raises.} =
  let config = AvailabilityConfig(guarantee: GuaranteeConfig(cores: CoreCount(2),
      validators: ValidatorCount(6),
    maxBytes: ByteLimit(2_000_000)), maxPresent: ElementLimit(2), maxBytes: ByteLimit(4_000_000))
  let raw = readFile(paramStr(1))
  var reportWire = newSeq[byte](raw.len)
  for i in 0..<raw.len: reportWire[i] = byte(raw[i]) # Fixture is independently encoded by the Python reference.
  let report = decodeOwnedReport(reportWire, 2)
  assert report.error == OwnershipError.None
  var guarantee = Guarantee(report: report.value, slot: GuaranteeSlot(255), credentialCount: 2)
  guarantee.credentials[1].validator = GuarantorIndex(1)
  var values = @[presentAssignment(guarantee, AssignmentSlot(0x01020304)),
    absentAssignment()]
  let encoded = availabilityStateEntry(values, config)
  assert encoded.error == AvailabilityError.None and array[31, byte](encoded.value.key)[0] == 10
  let standalone = encodeGuaranteeValue(guarantee, config.guarantee)
  assert standalone.error == GuaranteeError.None
  let inspected = inspectGuarantee(standalone.value, config.guarantee)
  assert inspected.error == GuaranteeError.None and inspected.value.consumed ==
      standalone.value.len
  var wire = encoded.value.value
  let decoded = decodeAvailabilityState(wire, config)
  assert decoded.error == AvailabilityError.None
  var parent = decoded.value.snapshot
  let detached = detachedChild(wire, config)
  let copied = availabilityAt(parent, AssignmentCoreIndex(0))
  assert copied.error == AvailabilityError.None and copied.value.present
  var edited = values[0].guarantee
  edited.credentials[0].validator = GuarantorIndex(5)
  values[0] = presentAssignment(edited, AssignmentSlot(0))
  parent = default(AvailabilitySnapshot)
  # Destroy original caller report and parent bytes before observing the copied retained child.
  for i in 0..<wire.len: wire[i] = 0
  for i in 0..<reportWire.len: reportWire[i] = 0
  assert uint32(copied.value.registered) == 0x01020304 and uint32(copied.value.guarantee.slot) == 255
  assert uint16(copied.value.guarantee.credentials[0].validator) == 0
  assert ownedReportInfo(copied.value.guarantee.report).error == OwnershipError.None
  var replay = newSeq[byte](raw.len)
  assert encodeOwnedReport(copied.value.guarantee.report, replay).error == OwnershipError.None
  # Compare copied octets without relying on any sequence/string memory layout.
  for i in 0..<raw.len: assert replay[i] == byte(raw[i])
  assert ownedReportInfo(detached.guarantee.report).error == OwnershipError.None
  let info = availabilityInfo(decoded.value.snapshot)
  assert info.error == AvailabilityError.None and info.value.cores == 2 and info.value.present == 1
  let absent = availabilityAt(decoded.value.snapshot, AssignmentCoreIndex(1))
  assert absent.error == AvailabilityError.None and not absent.value.present
  let invalid = availabilityAt(decoded.value.snapshot, AssignmentCoreIndex(high(uint64)))
  assert invalid.error == AvailabilityError.InvalidIndex
  let short = decodeAvailabilityState(encoded.value.value.toOpenArray(0, encoded.value.value.len-2), config)
  assert short.error == AvailabilityError.Truncated
  let empty = availabilityStateEntry([absentAssignment(),
      absentAssignment()], config)
  assert empty.error == AvailabilityError.None and empty.value.value == @[0'u8, 0]
  echo "PASS availability state: retained reports/guarantees, optional fields, independent timestamps and result/index guards"

# Fixture I/O must fail explicitly instead of passing a missing-fixture codec run.
try:
  main()
except:
  # Missing or unreadable trusted fixtures are setup failures.
  quit 2
