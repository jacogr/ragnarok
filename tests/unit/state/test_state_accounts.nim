# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed-value metadata contracts: no heap owner, independent source/input copies and failure
## guards.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/assertions
import std/syncio
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/bounded as codec_bounded

## All fixed decoded fields survive both input mutation and local scope exit without a retained owner.
proc captured(): ServiceMetadataRead =
  var code = default(array[32, byte])
  code[0] = 17
  code[31] = 255
  var source = ServiceMetadata(codeHash: CodeHash(code), balance: AccountBalance(high(uint64)),
    minimumAccumulationGas: Gas(128), minimumTransferGas: Gas(256),
        storageBytes: AccountStorageBytes(1),
    depositOffset: AccountBalance(42), storageItems: AccountStorageItems(high(uint32)),
        created: AccountSlot(high(uint32)),
    lastAccumulation: AccountSlot(0), parent: ServiceIndex(high(uint32)))
  let entry = serviceMetadataEntry(ServiceIndex(0x01020304), source, ByteLimit(105))
  assert entry.error == ServiceMetadataError.None and entry.value.value.len == ServiceMetadataBytes
  let key = array[31, byte](entry.value.key)
  assert key[0] == 255 and key[1] == 4 and key[3] == 3 and key[5] == 2 and key[7] == 1
  source = default(ServiceMetadata)
  assert entry.value.value[1] == 17 and entry.value.value[41] == 255
  var input = entry.value.value
  let decoded = decodeServiceMetadata(input, ByteLimit(105))
  assert decoded.error == ServiceMetadataError.None
  result = decoded.value
  for i in 0..<input.len: input[i] = 0 # Metadata copies cannot depend on caller storage after return.

## Validate all nominal fields and runtime result guards without introducing a private heap-backed snapshot.
proc main() =
  let value = captured()
  assert value.consumed == 105 and array[32, byte](value.metadata.codeHash)[0] == 17
  assert uint64(value.metadata.balance) == high(uint64) and uint64(
      value.metadata.depositOffset) == 42
  assert uint64(value.metadata.minimumAccumulationGas) == 128 and uint64(
      value.metadata.minimumTransferGas) == 256
  assert uint64(value.metadata.storageBytes) == 1 and uint32(value.metadata.storageItems) == high(uint32)
  assert uint32(value.metadata.created) == high(uint32) and uint32(
      value.metadata.lastAccumulation) == 0
  assert uint32(value.metadata.parent) == high(uint32)
  var copy = value.metadata
  copy.balance = AccountBalance(0)
  copy.codeHash = default(CodeHash)
  assert uint64(value.metadata.balance) == high(uint64) and array[32, byte](
      value.metadata.codeHash)[31] == 255
  let truncated = decodeServiceMetadata(@[0'u8], ByteLimit(105))
  assert truncated.error == ServiceMetadataError.Truncated
  let unsupported = decodeServiceMetadata(@[1'u8], ByteLimit(105))
  assert unsupported.error == ServiceMetadataError.UnsupportedVersion
  let overlong = decodeServiceMetadata(@[128'u8, 0], ByteLimit(105))
  assert overlong.error == ServiceMetadataError.NonCanonical
  let limited = serviceMetadataEntry(ServiceIndex(0), value.metadata, ByteLimit(104))
  assert limited.error == ServiceMetadataError.LimitExceeded
  let zero = serviceMetadataEntry(ServiceIndex(0), default(ServiceMetadata), ByteLimit(105))
  assert zero.error == ServiceMetadataError.None and zero.value.value == newSeq[byte](105)
  echo "PASS service metadata: fixed scope/source/input copies, all fields and guarded failures"

main()
