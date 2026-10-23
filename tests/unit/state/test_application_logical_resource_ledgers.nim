# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent complete-map, compact and retained raw-key ledgers admit exact policies and reject one-short bounds without changing frozen target authority.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_supplied_context]
import ../../../src/app/[collected_supplied_plan, collected_supplied_state]
import ../../../src/state/[current_logical, current_state, supplied_logical_inventory, inventory,
    manifest, store]
import ../../../src/codec/[bounded, state_trie]
proc main() {.raises.} =
  ## Read actual fixed accounting only after genuine complete qualification; no guessed cardinality or root equivalence substitutes a resource ledger.
  let fixture = collectedNativeFixture()
  let logical = suppliedNativeState(fixture)
  let original = logical.currentLogicalSource.value.currentStateInventory.value
  let compact = original.inventoryInfo.value
  let manifest = original.inventorySource.value.manifestInfo.value
  let raw = logical.currentLogicalInventory.value.suppliedLogicalInfo.value
  let snapshot = logical.currentLogicalContext.value.state
  let shape = snapshot.commitment
  assert shape.entries > 0 and shape.entries <= 128 and shape.nodes > 0
  var largest = 0'u64
  for i in 0..<shape.entries:
    let key = snapshot.keyAt(StateEntryIndex(i)).value
    largest = max(largest, uint64(snapshot.lookup(key).value.byteLength))
  assert largest > 0 and manifest.valueBytes > 0 and compact.facts > 0 and compact.descriptorBytes > 0
  assert raw.keys > 0 and raw.rawKeyBytes > 0 and raw.retainedBytes > 0
  var exact = collectedSuppliedTestLimits()
  exact.logical.inventory.manifest.services = ElementLimit(uint64(compact.services))
  exact.logical.inventory.manifest.serialized.items = ElementLimit(uint64(shape.entries))
  exact.logical.inventory.manifest.serialized.nodes = TrieNodeLimit(shape.nodes)
  exact.logical.inventory.manifest.serialized.perValue = ByteLimit(largest)
  exact.logical.inventory.manifest.serialized.totalValueBytes = ByteLimit(manifest.valueBytes)
  exact.logical.inventory.manifest.storageKeyBytes = ByteLimit(2)
  exact.logical.inventory.facts = ElementLimit(compact.facts)
  exact.logical.inventory.bytes = ByteLimit(compact.descriptorBytes)
  exact.logical.keys = ElementLimit(raw.keys)
  exact.logical.rawKeyBytes = ByteLimit(raw.rawKeyBytes)
  exact.logical.bytes = ByteLimit(raw.retainedBytes)
  let admitted = planCollectedSupplied(fixture.chain, fixture.receipt, exact).value
  assert executeCollectedSupplied(fixture.chain, admitted, fixture.declarations).error ==
      CollectedSuppliedError.None
  for boundary in 0..10:
    var short = exact
    case boundary
    of 0: short.logical.inventory.manifest.services = ElementLimit(uint64(compact.services)-1)
    of 1: short.logical.inventory.manifest.serialized.items = ElementLimit(uint64(shape.entries)-1)
    of 2: short.logical.inventory.manifest.serialized.nodes = TrieNodeLimit(shape.nodes-1)
    of 3: short.logical.inventory.manifest.serialized.totalValueBytes = ByteLimit(
        manifest.valueBytes-1)
    of 4: short.logical.inventory.manifest.serialized.perValue = ByteLimit(largest-1)
    of 5: short.logical.inventory.facts = ElementLimit(compact.facts-1)
    of 6: short.logical.inventory.bytes = ByteLimit(compact.descriptorBytes-1)
    of 7: short.logical.keys = ElementLimit(raw.keys-1)
    of 8: short.logical.bytes = ByteLimit(raw.retainedBytes-1)
    of 9: short.logical.rawKeyBytes = ByteLimit(raw.rawKeyBytes-1)
    else: short.logical.inventory.manifest.storageKeyBytes = ByteLimit(1)
    let plan = planCollectedSupplied(fixture.chain, fixture.receipt, short).value
    let refusal = executeCollectedSupplied(fixture.chain, plan, fixture.declarations)
    let expected = if boundary >= 7 and boundary <=
        9: CollectedSuppliedError.LogicalFailure else: CollectedSuppliedError.StateFailure
    assert refusal.error == expected # Complete matching/compact and extra raw-key capture remain separate independently bounded stages.
  var wide = exact
  wide.logical.keys = ElementLimit(high(uint64))
  wide.logical.rawKeyBytes = ByteLimit(high(uint64))
  wide.logical.bytes = ByteLimit(high(uint64))
  wide.logical.inventory.facts = ElementLimit(high(uint64))
  wide.logical.inventory.bytes = ByteLimit(high(uint64))
  wide.logical.inventory.manifest.services = ElementLimit(high(uint64))
  wide.logical.inventory.manifest.storageKeyBytes = ByteLimit(high(uint64))
  wide.logical.inventory.manifest.serialized.items = ElementLimit(high(uint64))
  wide.logical.inventory.manifest.serialized.nodes = TrieNodeLimit(high(uint64))
  wide.logical.inventory.manifest.serialized.perValue = ByteLimit(high(uint64))
  wide.logical.inventory.manifest.serialized.totalValueBytes = ByteLimit(high(uint64))
  let widePlan = planCollectedSupplied(fixture.chain, fixture.receipt, wide).value
  let result = executeCollectedSupplied(fixture.chain, widePlan, fixture.declarations).value
  assert result.currentLogicalSource.value.currentStateInventory.value.inventoryInfo.value.descriptorBytes ==
      compact.descriptorBytes
  assert uint64(admitted.collectedSuppliedLimits.value.logical.keys) == raw.keys
  echo "application-logical-resource-ledgers: ok"
try:
  main()
except:
  quit(2) # A quota refusal or maximum unsigned policy never becomes successful empty evidence or a native allocation request.
