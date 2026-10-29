# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal signed preimage inputs and request/value bytes verify canonical state fulfillment.

import std/assertions
import ../../src/state/accumulation/preimages as accumulation_preimages
import ../../src/state/[preimages, store]
import ../../src/codec/[bounded, composite, owned, header]
import ../../src/codec/state/[layout as state_layout, trie as state_trie,
    service_values as state_service_values]
import ../../src/crypto/primitives
import ./[report_context, pvm_accumulation_provision]

proc blockPreimageWire*(provided = false): seq[byte] =
  ## Literal canonical service/blob pairs include an empty blob, or actual guest-provided values.
  if provided: return @[2'u8, 42, 0, 0, 0, 1, 73, 99, 0, 0, 0, 1, 81]
  @[3'u8, 42, 0, 0, 0, 0, 42, 0, 0, 0, 2, 1, 2, 99, 0, 0, 0, 1, 3]
proc preimageRequests*(): seq[StateEntry] =
  ## All three requests enter the original signed parent, including the empty-blob request.
  @[provisionRequest(42, @[]), provisionRequest(42, @[1'u8, 2]), provisionRequest(99, @[3'u8])]
proc valueEntry(service: uint32, blob: seq[byte]): StateEntry =
  ## Namespace primitives frame literal values; they do not execute the transition being tested.
  let hash = ServicePreimageHash(array[32, byte](blake2b256(blob).value))
  servicePreimageEntry(ServiceIndex(service), hash, blob,
    ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(uint64(blob.len)))).value
proc checkBlockPreimages*(source: PreparedAccumulationPreimages,
    empty = false, provided = false) =
  ## Literal supplied timestamps and exact content cover empty values and genuine earlier guest fulfillment.
  let info = source.accumulationPreimagesInfo.value
  let state = source.accumulationPreimagesState.value
  assert uint32(info.slot) == 2
  assert info.admitted.items == (if empty: 0 elif provided: 2 else: 3)
  assert info.admitted.services == (if empty: 0 else: 2)
  assert uint64(info.admitted.bytes) == (if empty: 0'u64 elif provided: 2'u64 else: 3'u64)
  if not empty:
    let services = if provided: @[42'u32, 99] else: @[42'u32, 42, 99]
    let blobs = if provided: @[@[73'u8], @[81'u8]] else: @[newSeq[byte](), @[1'u8, 2], @[3'u8]]
    for index, service in services:
      let request = provisionRequest(service, blobs[index])
      assert state.lookup(request.key).value.bytes == @[1'u8, 2, 0, 0, 0]
      let entry = valueEntry(service, blobs[index])
      assert state.lookup(entry.key).value.bytes == entry.value # Empty payloads remain initialized exact values.
