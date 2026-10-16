## Supplementary scope retention, fixed-copy independence and result/owner/index guards for output logs.
import ../../src/[state_outputs, bounded]

## Default/failed tagged alternatives must reject successful payload reads under checked optimized builds.
proc guarded[T](value: OutputLogResult[T]) =
  var caught = false
  try:
    discard value.value # Failure cannot fabricate a complete commitment or owner.
  except FieldDefect:
    caught = true # Field guards stay enabled under ARC/Clang LTO.
  doAssert caught

## Capture an immutable sequence that survives local source/wire scope and all later caller mutation.
proc captured(config: OutputLogConfig): OutputLogSnapshot =
  var bytes: array[32, byte]
  bytes[0] = 17
  bytes[31] = 255
  var values = @[AccumulationOutput(service: ServiceIndex(high(uint32)),
      commitment: OutputCommitment(bytes)),
    AccumulationOutput(service: ServiceIndex(1), commitment: OutputCommitment(bytes))]
  let encoded = outputLogEntry(values, config)
  doAssert encoded.error == OutputLogError.None and array[31, byte](encoded.value.key)[0] == 16
  values[0] = default(AccumulationOutput)
  doAssert encoded.value.value[1] == 255 and encoded.value.value[5] == 17
  var wire = encoded.value.value
  let parsed = decodeOutputLog(wire, config)
  doAssert parsed.error == OutputLogError.None and parsed.value.consumed == wire.len
  result = parsed.value.snapshot
  for i in 0..<wire.len: wire[i] = 0 # All retained pairs must be independent copies.

## Exercise sequence-order preservation and fixed extraction copies through only public owner operations.
proc main() =
  doAssert sizeof(int) == 8 and sizeof(AccumulationOutput) == 36
  let config = OutputLogConfig(items: ElementLimit(2), maxBytes: ByteLimit(73))
  let owner = captured(config)
  doAssert outputLogCount(owner).value == 2
  var first = outputLogAt(owner, OutputLogIndex(0)).value
  doAssert uint32(first.service) == high(uint32) and array[32, byte](first.commitment)[0] == 17
  doAssert uint32(outputLogAt(owner, OutputLogIndex(1)).value.service) == 1
  first.service = ServiceIndex(0)
  first.commitment = default(OutputCommitment)
  doAssert array[32, byte](outputLogAt(owner, OutputLogIndex(0)).value.commitment)[31] == 255
  var replaced = owner
  replaced = default(OutputLogSnapshot)
  guarded(outputLogCount(replaced))
  guarded(outputLogAt(replaced, OutputLogIndex(0)))
  doAssert outputLogCount(owner).value == 2
  let invalid = outputLogAt(owner, OutputLogIndex(high(uint64)))
  doAssert invalid.error == OutputLogError.InvalidIndex
  guarded(invalid)
  guarded(default(OutputLogResult[OutputLogRead]))
  let empty = decodeOutputLog(@[0'u8], OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(1)))
  doAssert empty.error == OutputLogError.None and outputLogCount(empty.value.snapshot).value == 0
  guarded(outputLogAt(empty.value.snapshot, OutputLogIndex(0)))
  let late = decodeOutputLog(@[2'u8], config)
  doAssert late.error == OutputLogError.Truncated
  guarded(late)
  let limited = decodeOutputLog(@[0'u8], OutputLogConfig(items: ElementLimit(0),
      maxBytes: ByteLimit(0)))
  doAssert limited.error == OutputLogError.LimitExceeded
  guarded(limited)
  echo "PASS output log: scope retention, ordered pairs, independent fixed copies and result/index guards"

main()
