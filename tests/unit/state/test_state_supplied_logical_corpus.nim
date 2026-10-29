# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Retained raw keys and detached complete declarations reproduce independent whole-map checkpoints across full-width/empty shapes.
import std/[assertions, envvars, strutils, syncio]
import ../../support/[state_complete_serialization_context, state_inventory_context,
    supplied_logical_context, supplied_services_context]
import ../../../src/state/[checkpoint, store, manifest, global_snapshot, validated_checkpoint, inventory]
import ../../../src/state/supplied/[logical_inventory as supplied_logical_inventory,
    services as supplied_services]
import ../../../src/codec/bounded
import ../../../src/codec/state/[trie as state_trie, composition as state_composition,
    requests as state_requests]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Full raw-key/payload projection must work after matching with the hash backend disabled.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Projection/copy queries and all early resource refusals hash nothing.
const
  mapLimits = StateTrieLimits(items: ElementLimit(64), nodes: TrieNodeLimit(4096),
      perValue: ByteLimit(65536), totalValueBytes: ByteLimit(262144))
  limits = StateCheckpointLimits(checkpointBytes: ByteLimit(524288), store: StateStoreLimits(
      trie: mapLimits, writes: ElementLimit(64), writeValueBytes: ByteLimit(262144)),
      globals: GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
      maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144)), manifest: StateManifestLimits(
      services: ElementLimit(4), serialized: mapLimits, storageKeyBytes: ByteLimit(65)))
proc check(input: seq[byte], services: seq[StateService]) =
  ## Independently authored root and full envelope are restored before any native key retention or detached reconstruction.
  fail(0)
  var root = default(array[32, byte])
  for i in 0..<32: root[i] = input[25+i]
  let restored = decodeValidatedCheckpoint(input, StateRoot(root), services, inventoryProfile, limits).value
  let logical = captureSuppliedLogicalInventory(restored, services, suppliedLogicalTestLimits).value
  let compact = logical.suppliedInventory.value
  var rawBytes = 0'u64
  var valueBytes = 0'u64
  var maximum = 0'u64
  for item in services:
    rawBytes += uint64(item.storage[0].key.len)
    valueBytes += uint64(item.storage[0].key.len+item.storage[0].value.len+item.preimages[0].value.len)
    for size in [item.storage[0].key.len, item.storage[0].value.len, item.preimages[0].value.len]:
      if uint64(size) > maximum: maximum = uint64(size)
  let info = logical.suppliedLogicalInfo.value
  assert info.keys == uint64(services.len) and info.rawKeyBytes == rawBytes
  var exactCapture = suppliedLogicalTestLimits
  exactCapture.keys = ElementLimit(info.keys)
  exactCapture.rawKeyBytes = ByteLimit(rawBytes)
  exactCapture.bytes = ByteLimit(info.retainedBytes)
  assert captureSuppliedLogicalInventory(restored, services, exactCapture).error ==
      SuppliedLogicalError.None
  let descriptorBytes = uint64(services.len) * uint64(sizeof(StateService)+sizeof(
      StateStorageItem)+sizeof(StatePreimageItem)+sizeof(StateRequestItem))
  let exactCopy = SuppliedServicesLimits(services: ElementLimit(uint64(services.len)),
      facts: ElementLimit(uint64(4*services.len)), perValue: ByteLimit(maximum), bytes: ByteLimit(
      descriptorBytes+valueBytes))
  fail(1)
  var copied = copySuppliedServices(logical, exactCopy).value
  for i, item in services:
    let service = InventoryServiceIndex(uint64(i))
    let key = logical.copySuppliedStorageKey(service, InventoryStorageIndex(0), ByteLimit(uint64(
        item.storage[0].key.len))).value
    assert key == item.storage[0].key
    assert compact.inventoryStorageAt(service, InventoryStorageIndex(0)).value.keyBytes == uint64(key.len)
    assert uint32(copied[i].service) == uint32(item.service) and copied[i].storage[0].key ==
        item.storage[0].key
    assert copied[i].storage[0].value == item.storage[0].value and copied[i].preimages[0].value ==
        item.preimages[0].value
    assert array[32, byte](copied[i].preimages[0].hash) == array[32, byte](item.preimages[0].hash)
    assert copied[i].requests[0].history.state == item.requests[0].history.state
    assert uint32(copied[i].requests[0].length) == uint32(item.requests[0].length)
  var short = exactCopy
  short.bytes = ByteLimit(descriptorBytes+valueBytes-1)
  assert copySuppliedServices(logical, short).error == SuppliedServicesError.LimitExceeded
  short = exactCopy
  short.facts = ElementLimit(uint64(4*services.len-1))
  assert copySuppliedServices(logical, short).error == SuppliedServicesError.LimitExceeded
  assert calls() == 0
  fail(0)
  let composed = composeState(restored.manifestGlobals.value.globalChapters.value, copied,
      mapLimits, ByteLimit(65)).value
  var entries: seq[StateEntry] = @[]
  for i in 0..<composed.stateCommitment.value.entries:
    entries.add(composed.stateEntryAt(state_composition.StateEntryIndex(uint64(i))).value)
  let snapshot = newStateStore(entries, limits.store).value.snapshot.value
  assert encodeFullCheckpoint(snapshot, limits.checkpointBytes).value == input
  copied[0].storage[0].key = @[byte(99)]
  fail(1)
  assert copySuppliedServices(logical, exactCopy).value[0].storage[0].key == services[0].storage[0].key
  assert calls() == 0
  fail(0)
proc main() {.raises.} =
  ## Forty independently authored maps are qualified in single and both multi-service declaration orders, without skipping empty raw keys.
  var row = 0
  for line in readFile(getEnv("RAGNAROK_COMPLETE_SERIALIZATION")).splitLines():
    if line.len == 0: continue # SHA-pinned fixtures end with one newline.
    check(serializationOctets(line), @[serializationService(row)])
    inc row
  assert row == 32
  row = 0
  for line in readFile(getEnv("RAGNAROK_MULTISERVICE_SERIALIZATION")).splitLines():
    if line.len == 0: continue
    var original: seq[StateService] = @[]
    var reverse: seq[StateService] = @[]
    for i in 0..<4:
      original.add(serializationService(4*row+i))
      reverse.add(serializationService(4*row+3-i))
    check(serializationOctets(line), original)
    check(serializationOctets(line), reverse)
    inc row
  assert row == 8
  echo "state-supplied-logical-corpus: ok (48 cases)"
try:
  main()
except:
  quit(2) # Setup/independent root failure cannot qualify key/payload reconstruction evidence.
