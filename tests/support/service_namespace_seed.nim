# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted opt-in fixture namespaces enter complete original maps before roots and signatures.
import std/assertions
import ../../src/codec/[bounded, state_layout, state_trie, state_accounts, state_service_values,
    state_requests, state_composition]
type ServiceNamespaceSeed* = object ## Author only children; original executable metadata stays authoritative.
  service*: ServiceIndex
  storage*: seq[StateStorageItem]
  preimages*: seq[StatePreimageItem]
  requests*: seq[StateRequestItem]
proc seedServiceNamespaces*(entries: var seq[StateEntry], seeds: openArray[ServiceNamespaceSeed],
    perValue = ByteLimit(65)) =
  ## Tiny trusted fixture bounds prove footprint arithmetic; duplicate physical keys still fail the real store constructor.
  assert seeds.len <= 2
  assert uint64(perValue) <= 65536 # Trusted fixture values retain a small proved native/footprint extent.
  let values = ServiceEntryLimits(keyBytes: ByteLimit(65), valueBytes: perValue)
  let requests = RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
      items: ElementLimit(3), maxBytes: ByteLimit(13)))
  for seed in seeds:
    assert uint32(seed.service) == 42 or uint32(seed.service) == 99
    assert seed.storage.len <= 16 and seed.preimages.len <= 16 and seed.requests.len <= 16
    var octets = 0'u64
    for item in seed.storage:
      assert item.key.len <= 65 and uint64(item.value.len) <= uint64(perValue)
      octets+=34'u64+uint64(item.key.len)+uint64(item.value.len)
    for item in seed.requests:
      assert uint32(item.length) <= 65536
      octets+=81'u64+uint64(uint32(item.length))
    let key = chapterServiceKey(StateChapter(255), seed.service)
    var found = false
    for i in 0..<entries.len:
      if array[31, byte](entries[i].key) == array[31, byte](key):
        assert not found
        found = true
        let decoded = decodeServiceMetadata(entries[i].value, ByteLimit(105))
        assert decoded.error == ServiceMetadataError.None and decoded.value.consumed == entries[i].value.len
        var metadata = decoded.value.metadata
        metadata.storageItems = AccountStorageItems(uint32(seed.storage.len+2*seed.requests.len))
        metadata.storageBytes = AccountStorageBytes(octets)
        entries[i] = serviceMetadataEntry(seed.service, metadata, ByteLimit(
            105)).value # Retain original code/gas/balance and lifetime fields.
    assert found
    for item in seed.storage:
      entries.add(serviceStorageEntry(seed.service, item.key, item.value, values).value)
    for item in seed.preimages:
      assert uint64(item.value.len) <= uint64(perValue)
      entries.add(servicePreimageEntry(seed.service, item.hash, item.value, values).value)
    for item in seed.requests:
      entries.add(serviceRequestEntry(seed.service, item.hash, item.length, item.history,
          requests).value)
