## Supplementary retained key/value lifetime, independent copies, atomic destination and result contracts.
import ../../src/codec/[state_service_values, bounded]

## Default/failed results must reject inactive successful-payload reads under checked optimized builds.
proc guarded[T](value: ServiceValueResult[T]) =
  var caught = false
  try:
    discard value.value # Failure cannot fabricate keys, owners or copy progress.
  except FieldDefect:
    caught = true # Field checks stay active under ARC/Clang LTO.
  doAssert caught

## An opaque retained value survives source key/value scope and every caller mutation.
proc captured(): ServiceValueSnapshot =
  var key = @[1'u8, 2, 3]
  var value = @[17'u8, 18, 19]
  let limits = ServiceEntryLimits(keyBytes: ByteLimit(3), valueBytes: ByteLimit(3))
  let encoded = serviceStorageEntry(ServiceIndex(0x01020304), key, value, limits)
  doAssert encoded.error == ServiceValueError.None
  for i in 0..<key.len: key[i] = 0 # Source mutation cannot change the derived fixed key.
  let captured = captureServiceValue(ServiceIndex(0x01020304), encoded.value.key, value, ByteLimit(3))
  doAssert captured.error == ServiceValueError.None
  result = captured.value
  for i in 0..<value.len: value[i] = 0 # Complete retained copy outlives caller input.

## Validate immutable identity binding, independent copies and failure-only/atomic behavior through public APIs.
proc main() =
  let owner = captured()
  let info = serviceValueInfo(owner).value
  doAssert uint32(info.service) == 0x01020304 and info.length == 3
  var output = @[77'u8, 77, 77, 77]
  let copied = copyServiceValue(owner, output)
  doAssert copied.error == ServiceValueError.None and copied.value == 3 and output == @[17'u8, 18, 19, 77]
  output[0] = 0
  doAssert serviceValueEntry(owner, ByteLimit(3)).value.value == @[17'u8, 18, 19]
  var keyCopy = array[31, byte](info.key)
  keyCopy[1] = keyCopy[1] xor 255
  doAssert array[31, byte](serviceValueInfo(owner).value.key)[1] != keyCopy[1]
  var short = @[77'u8, 77]
  let capacity = copyServiceValue(owner, short)
  doAssert capacity.error == ServiceValueError.OutputTooSmall and short == @[77'u8, 77]
  guarded(capacity)
  var replaced = owner
  replaced = default(ServiceValueSnapshot)
  guarded(serviceValueInfo(replaced))
  guarded(copyServiceValue(replaced, output))
  guarded(serviceValueEntry(replaced, ByteLimit(3)))
  doAssert serviceValueInfo(owner).value.length == 3
  let narrow = serviceValueEntry(owner, ByteLimit(2))
  doAssert narrow.error == ServiceValueError.LimitExceeded
  guarded(narrow)
  let mismatch = captureServiceValue(ServiceIndex(0), info.key, @[1'u8], ByteLimit(1))
  doAssert mismatch.error == ServiceValueError.InvalidServiceKey
  guarded(mismatch)
  guarded(default(ServiceValueResult[StateKey]))
  let empty = captureServiceValue(info.service, info.key, @[], ByteLimit(0))
  doAssert empty.error == ServiceValueError.None and serviceValueInfo(empty.value).value.length == 0
  doAssert copyServiceValue(empty.value, output).value == 0 and serviceValueEntry(empty.value,
      ByteLimit(0)).value.value.len == 0
  let limits = ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(0))
  let hash = default(ServicePreimageHash)
  let storage = serviceStorageKey(ServiceIndex(0), array[32, byte](hash), ByteLimit(32))
  let preimage = servicePreimageEntry(ServiceIndex(0), hash, @[], limits)
  doAssert storage.error == ServiceValueError.None and preimage.error == ServiceValueError.None
  doAssert array[31, byte](storage.value) != array[31, byte](preimage.value.key)
  echo "PASS service values: retained identity/bytes, scope copies, raw empties and atomic/result guards"

main()
