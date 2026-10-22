# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently encoded complete chapter/service fixtures support compact provenance and consistency consumers.
import ../../src/state/[manifest, global_snapshot, store, inventory]
import ../../src/codec/[bounded, assurances, state_consensus, state_layout, state_trie,
  state_accounts, state_service_values, state_requests, state_composition]
const
  inventoryProfile* = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
    previous: ValidatorCount(6), epochSlots: EpochSlots(2))
  inventoryMapLimits* = StateTrieLimits(items: ElementLimit(64), nodes: TrieNodeLimit(1024),
    perValue: ByteLimit(65536), totalValueBytes: ByteLimit(262144))
  inventoryManifestLimits* = StateManifestLimits(services: ElementLimit(16),
      serialized: inventoryMapLimits,
    storageKeyBytes: ByteLimit(1024))
  inventoryCaptureLimits* = StateInventoryLimits(manifest: inventoryManifestLimits,
    facts: ElementLimit(128), bytes: ByteLimit(65536))
proc inventoryServices*(): seq[StateService] =
  ## Literal Blake2b-256(abc), complete request linkage and independently calculated footprint are authored test facts.
  let hash = ServicePreimageHash([byte(0xbd), 0xdd, 0x81, 0x3c, 0x63, 0x42, 0x39, 0x72, 0x31, 0x71,
      0xef, 0x3f, 0xee, 0x98, 0x57, 0x9b, 0x94, 0x96, 0x4e, 0x3b, 0xb1, 0xcb, 0x3e, 0x42, 0x72,
      0x62, 0xc8, 0xc0, 0x68, 0xd5, 0x23, 0x19])
  @[StateService(service: ServiceIndex(7), metadata: ServiceMetadata(balance: AccountBalance(1000),
      supervisorBalance: AccountBalance(20), supervisor: ServiceIndex(7),
          supervisorCreated: AccountSlot(2),
      created: AccountSlot(2), storageItems: AccountStorageItems(3),
          storageBytes: AccountStorageBytes(121)),
      storage: @[StateStorageItem(key: @[byte(1), 2], value: @[byte(3)])],
      preimages: @[StatePreimageItem(hash: hash, value: @[byte(97), 98, 99])],
      requests: @[StateRequestItem(hash: hash, length: RequestLength(3), history: availableHistory(
          RequestSlot(3)))]),
    StateService(service: ServiceIndex(8), metadata: ServiceMetadata(balance: AccountBalance(1000),
      supervisor: ServiceIndex(7), supervisorCreated: AccountSlot(2), created: AccountSlot(4)))]
proc inventoryManifest*(chapters: seq[seq[byte]], services: openArray[
    StateService]): ValidatedStateManifest =
  ## Build the source through lower-level entry encoders, independently of whole composition's assembly loop.
  var entries: seq[StateEntry] = @[]
  for i in 1..16:
    entries.add(StateEntry(key: chapterKey(StateChapter(i)), value: chapters[
        i-1])) # Original independent global fixture bytes.
  for item in services:
    entries.add(serviceMetadataEntry(item.service, item.metadata, ByteLimit(105)).value)
    for row in item.storage:
      entries.add(serviceStorageEntry(item.service, row.key, row.value,
        ServiceEntryLimits(keyBytes: ByteLimit(1024), valueBytes: ByteLimit(65536))).value)
    for row in item.preimages:
      entries.add(servicePreimageEntry(item.service, row.hash, row.value,
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(65536))).value)
    for row in item.requests:
      entries.add(serviceRequestEntry(item.service, row.hash, row.length, row.history,
        RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
          items: ElementLimit(3), maxBytes: ByteLimit(13)))).value)
  let source = newStateStore(entries, StateStoreLimits(trie: inventoryMapLimits,
    writes: ElementLimit(64), writeValueBytes: ByteLimit(262144))).value.snapshot.value
  let globals = validateGlobalState(source, inventoryProfile, GlobalStateLimits(
    chapter: StateChapterPolicy(items: ElementLimit(1000), maxBytes: ByteLimit(65536)),
    totalBytes: ByteLimit(262144))).value
  validateStateManifest(globals, services, inventoryManifestLimits).value
