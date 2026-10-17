import ../../support/arc_evidence
## Privileged native misuse test: safe public APIs cannot expose a backing alias, but atomic copy still guards it.
import std/[assertions, syncio]
include ../../../src/codec/state_service_values

## Exact and shifted retained-storage destinations must reject before modifying any captured byte.
proc main() =
  let key = serviceStorageKey(ServiceIndex(1), @[1'u8], ByteLimit(1)).value
  let owner = captureServiceValue(ServiceIndex(1), key, @[17'u8, 18, 19], ByteLimit(3)).value
  let data = owner.data
  assert data != nil
  let exact = copyServiceValue(owner, data.bytes)
  assert exact.error == ServiceValueError.AliasedBuffers and data.bytes == @[17'u8, 18, 19]
  let shifted = copyServiceValue(owner, data.bytes.toOpenArray(1, 2))
  assert shifted.error == ServiceValueError.OutputTooSmall and data.bytes == @[17'u8, 18, 19]
  echo "PASS service values: private native alias rejection and unchanged backing bytes"

main()

# The observer is test-only; production-linked corpora use the unmodified primitive bridge.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
# Copied call counters distinguish complete preflight from backend refusal.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Escape a captured value after all local source keys, bytes and derived entries retire.
proc escaped(service: ServiceIndex, marker: byte): ServiceValueSnapshot =
  var original = @[marker, 128'u8, 0, 255]
  var key = @[1'u8, 2, 3]
  let limits = ServiceEntryLimits(keyBytes: ByteLimit(3), valueBytes: ByteLimit(4))
  let encoded = serviceStorageEntry(service, key, original, limits)
  assert encoded.error == ServiceValueError.None
  result = captureServiceValue(service, encoded.value.key, original, ByteLimit(4)).value
  # Neither original source may remain the backing storage of retained key/value data.
  for i in 0..<original.len: original[i] = 0
  # Derived fixed keys must not retain original raw-key coordinates.
  for i in 0..<key.len: key[i] = 0

## Exercise final-owner release, fixed metadata copies, output independence and exact atomic failures.
proc cycle() =
  fail(0)
  var owner = escaped(ServiceIndex(1), 17)
  let retained = owner
  owner = escaped(ServiceIndex(2), 29)
  assert uint32(serviceValueInfo(retained).value.service) == 1
  assert uint32(serviceValueInfo(owner).value.service) == 2
  var info = serviceValueInfo(retained).value
  info.service = ServiceIndex(0)
  info.key = default(StateKey)
  info.length = 0
  assert serviceValueInfo(retained).value.length == 4
  var output = @[77'u8, 77, 77, 77, 77]
  assert copyServiceValue(retained, output).value == 4
  assert output == @[17'u8, 128, 0, 255, 77]
  output[0] = 0
  var emitted = serviceValueEntry(retained, ByteLimit(4)).value
  emitted.value[0] = 0
  assert serviceValueEntry(retained, ByteLimit(4)).value.value[0] == 17
  owner = default(ServiceValueSnapshot)
  assert serviceValueInfo(owner).error == ServiceValueError.InvalidOwner
  var short = @[77'u8, 77, 77]
  assert copyServiceValue(retained, short).error == ServiceValueError.OutputTooSmall
  assert short == @[77'u8, 77, 77]
  let data = retained.data
  assert data != nil
  assert overlaps(data, data.bytes.toOpenArray(1, 3))
  assert copyServiceValue(retained, data.bytes).error == ServiceValueError.AliasedBuffers
  assert data.bytes == @[17'u8, 128, 0, 255]
  let empty = captureServiceValue(ServiceIndex(1), serviceValueInfo(retained).value.key, [],
      ByteLimit(0)).value
  assert serviceValueInfo(empty).value.length == 0
  assert copyServiceValue(empty, output).value == 0
  assert output == @[0'u8, 128, 0, 255, 77]
  fail(1)
  let limits = ServiceEntryLimits(keyBytes: ByteLimit(3), valueBytes: ByteLimit(4))
  assert serviceStorageEntry(ServiceIndex(1), [1'u8, 2, 3], [17'u8], limits).error ==
      ServiceValueError.BackendFailure
  assert hashCalls() == 1
  fail(1)
  assert servicePreimageEntry(ServiceIndex(1), default(ServicePreimageHash), [17'u8],
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).error ==
      ServiceValueError.BackendFailure
  assert hashCalls() == 1
  fail(1)
  # Value policy must reject before raw-key scratch and any native hashing attempt.
  assert serviceStorageEntry(ServiceIndex(1), [1'u8], [17'u8], ServiceEntryLimits(
      keyBytes: ByteLimit(1), valueBytes: ByteLimit(0))).error == ServiceValueError.LimitExceeded
  assert hashCalls() == 0
  assert serviceStorageKey(ServiceIndex(1), [1'u8], ByteLimit(0)).error ==
      ServiceValueError.LimitExceeded
  assert servicePreimageKey(ServiceIndex(1), default(ServicePreimageHash), ByteLimit(31)).error ==
      ServiceValueError.LimitExceeded
  assert hashCalls() == 0
  fail(0)
  assert serviceStorageEntry(ServiceIndex(1), [1'u8, 2, 3], [17'u8], limits).error ==
      ServiceValueError.None
  assert hashCalls() == 1

# Test native extent arithmetic without fabricated open arrays or advertised-size allocations.
assert storageExtent(0).value == 4
assert storageExtent(high(int)-4).value == high(int)
assert storageExtent(high(int)-3).error == ServiceValueError.LengthOverflow
assert storageExtent(high(int)).error == ServiceValueError.LengthOverflow
# Warm all retained/replaced/error paths and observer bookkeeping before measuring live occupancy.
for i in 0..<100: cycle()
let beforeRelease = getOccupiedMem()
# Every private owner, nested source and scratch allocation retires at scope exit.
for i in 0..<1000: cycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("service_values_private", 1000, beforeRelease, afterRelease)
echo "SERVICE_VALUES_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony service values: retained owners, atomic aliases, backend refusal/recovery and scoped release passed"
