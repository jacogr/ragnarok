# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Project-only fixed-copy, preflight and byte-position checks; metadata has no heap-backed
## owner.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import ../../support/arc_evidence
import std/[assertions, syncio]
include ../../../src/codec/state_accounts

## Construct complete fixed fields independently of decoder offsets or encoded payloads.
proc source(marker: byte): ServiceMetadata =
  var code = default(array[32, byte])
  code[0] = marker
  code[31] = 255
  ServiceMetadata(codeHash: CodeHash(code), balance: AccountBalance(high(uint64)),
    minimumAccumulationGas: Gas(high(uint64)), minimumTransferGas: Gas(128),
    storageBytes: AccountStorageBytes(high(uint64)), depositOffset: AccountBalance(42),
    storageItems: AccountStorageItems(high(uint32)), created: AccountSlot(high(uint32)),
    lastAccumulation: AccountSlot(0), parent: ServiceIndex(high(uint32)))

## Return a fixed value after source fields and all mutable wire arrays retire.
proc escaped(marker: byte): ServiceMetadataRead =
  var original = source(marker)
  let encoded = serviceMetadataEntry(ServiceIndex(high(uint32)), original, ByteLimit(89))
  assert encoded.error == ServiceMetadataError.None
  original = default(ServiceMetadata)
  var wire = encoded.value.value
  let parsed = decodeServiceMetadata(wire, ByteLimit(89))
  assert parsed.error == ServiceMetadataError.None
  result = parsed.value
  # No decoded fixed field may retain caller bytes or detached coordinates.
  for i in 0..<wire.len: wire[i] = 0

## Each scope releases fresh encoded bytes while copied metadata remains independent of replacement.
proc cycle() =
  var first = escaped(17)
  let retained = first
  first = escaped(29)
  assert array[32, byte](retained.metadata.codeHash)[0] == 17
  assert array[32, byte](first.metadata.codeHash)[0] == 29
  assert retained.consumed == 89
  var copy = retained.metadata
  copy = default(ServiceMetadata)
  first = default(ServiceMetadataRead)
  assert array[32, byte](retained.metadata.codeHash)[31] == 255
  assert uint64(retained.metadata.balance) == high(uint64)
  assert uint64(retained.metadata.minimumAccumulationGas) == high(uint64)
  assert uint64(retained.metadata.minimumTransferGas) == 128
  assert uint64(retained.metadata.storageBytes) == high(uint64)
  assert uint64(retained.metadata.depositOffset) == 42
  assert uint32(retained.metadata.storageItems) == high(uint32)
  assert uint32(retained.metadata.created) == high(uint32)
  assert uint32(retained.metadata.lastAccumulation) == 0
  assert uint32(retained.metadata.parent) == high(uint32)
  var wire = serviceMetadataEntry(ServiceIndex(0), source(43), ByteLimit(high(uint64))).value.value
  wire.add(255'u8)
  let suffix = decodeServiceMetadata(wire, ByteLimit(89))
  assert suffix.error == ServiceMetadataError.None and suffix.value.consumed == 89
  wire.setLen(88)
  let beforeFailure = getOccupiedMem()
  assert decodeServiceMetadata(wire, ByteLimit(89)).error == ServiceMetadataError.Truncated
  assert decodeServiceMetadata([], ByteLimit(88)).error == ServiceMetadataError.LimitExceeded
  assert decodeServiceMetadata([1'u8], ByteLimit(89)).error ==
      ServiceMetadataError.UnsupportedVersion
  assert decodeServiceMetadata([128'u8, 0], ByteLimit(89)).error ==
      ServiceMetadataError.NonCanonical
  assert beforeFailure == getOccupiedMem()
  assert serviceMetadataEntry(ServiceIndex(0), source(43), ByteLimit(88)).error ==
      ServiceMetadataError.LimitExceeded

# Independent literal words check low/high offsets and unsigned high bits without platform-endian casts.
let octets = [0'u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 255]
assert read64(octets, 0) == 0x0706050403020100'u64
assert read64(octets, 8) == 0xff0e0d0c0b0a0908'u64
assert read32(octets, 0) == 0x03020100'u32
assert read32(octets, 12) == 0xff0e0d0c'u32
# Warm allocator bookkeeping for scoped encoded entries and all fixed-copy/failure paths.
for i in 0..<100: cycle()
let beforeRelease = getOccupiedMem()
# Metadata contains no references; fresh encoded bytes still must retire on every completed scope.
for i in 0..<1000: cycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("state_accounts_private", 1000, beforeRelease, afterRelease)
echo "ACCOUNTS_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony account metadata: escaped/replaced fixed values, byte positions and scoped release passed"
