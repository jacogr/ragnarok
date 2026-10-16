## Fixed-value metadata contracts: no heap owner, independent source/input copies and failure guards.
import ../../src/codec/[state_accounts, bounded]

## Default and failed results must reject inactive successful-payload reads under checked optimized builds.
proc guarded[T](parsed: ServiceMetadataResult[T]) =
  var caught = false
  try:
    discard parsed.value # Failed/default results cannot fabricate metadata or progress.
  except FieldDefect:
    caught = true # Field guards remain active under ARC/Clang LTO.
  doAssert caught

## All fixed decoded fields survive both input mutation and local scope exit without a retained owner.
proc captured(): ServiceMetadataRead =
  var code: array[32, byte]
  code[0] = 17
  code[31] = 255
  var source = ServiceMetadata(codeHash: CodeHash(code), balance: AccountBalance(high(uint64)),
    minimumAccumulationGas: Gas(128), minimumTransferGas: Gas(256),
        storageBytes: AccountStorageBytes(1),
    depositOffset: AccountBalance(42), storageItems: AccountStorageItems(high(uint32)),
        created: AccountSlot(high(uint32)),
    lastAccumulation: AccountSlot(0), parent: ServiceIndex(high(uint32)))
  let entry = serviceMetadataEntry(ServiceIndex(0x01020304), source, ByteLimit(89))
  doAssert entry.error == ServiceMetadataError.None and entry.value.value.len == ServiceMetadataBytes
  let key = array[31, byte](entry.value.key)
  doAssert key[0] == 255 and key[1] == 4 and key[3] == 3 and key[5] == 2 and key[7] == 1
  source = default(ServiceMetadata)
  doAssert entry.value.value[1] == 17 and entry.value.value[33] == 255
  var input = entry.value.value
  let decoded = decodeServiceMetadata(input, ByteLimit(89))
  doAssert decoded.error == ServiceMetadataError.None
  result = decoded.value
  for i in 0..<input.len: input[i] = 0 # Metadata copies cannot depend on caller storage after return.

## Validate all nominal fields and runtime result guards without introducing a private heap-backed snapshot.
proc main() =
  let value = captured()
  doAssert value.consumed == 89 and array[32, byte](value.metadata.codeHash)[0] == 17
  doAssert uint64(value.metadata.balance) == high(uint64) and uint64(
      value.metadata.depositOffset) == 42
  doAssert uint64(value.metadata.minimumAccumulationGas) == 128 and uint64(
      value.metadata.minimumTransferGas) == 256
  doAssert uint64(value.metadata.storageBytes) == 1 and uint32(value.metadata.storageItems) == high(uint32)
  doAssert uint32(value.metadata.created) == high(uint32) and uint32(
      value.metadata.lastAccumulation) == 0
  doAssert uint32(value.metadata.parent) == high(uint32)
  var copy = value.metadata
  copy.balance = AccountBalance(0)
  copy.codeHash = default(CodeHash)
  doAssert uint64(value.metadata.balance) == high(uint64) and array[32, byte](
      value.metadata.codeHash)[31] == 255
  guarded(default(ServiceMetadataResult[ServiceMetadataRead]))
  let truncated = decodeServiceMetadata(@[0'u8], ByteLimit(89))
  doAssert truncated.error == ServiceMetadataError.Truncated
  guarded(truncated)
  let unsupported = decodeServiceMetadata(@[1'u8], ByteLimit(89))
  doAssert unsupported.error == ServiceMetadataError.UnsupportedVersion
  guarded(unsupported)
  let overlong = decodeServiceMetadata(@[128'u8, 0], ByteLimit(89))
  doAssert overlong.error == ServiceMetadataError.NonCanonical
  guarded(overlong)
  let limited = serviceMetadataEntry(ServiceIndex(0), value.metadata, ByteLimit(88))
  doAssert limited.error == ServiceMetadataError.LimitExceeded
  guarded(limited)
  let zero = serviceMetadataEntry(ServiceIndex(0), default(ServiceMetadata), ByteLimit(89))
  doAssert zero.error == ServiceMetadataError.None and zero.value.value == newSeq[byte](89)
  echo "PASS service metadata: fixed scope/source/input copies, all fields and guarded failures"

main()
