# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real complete-namespace forget/restore guests and literal history observations for collected Services successors.
import std/assertions
import ./[current_namespace_context, current_namespace_execution_context, pvm_accumulation_program,
    current_logical_proof_context]
import ../../src/codec/[report_owned, state_accounts, state_requests, state_service_values, bounded]
import ../../src/state/[current_logical, supplied_logical_inventory, inventory,
    accumulation_current_update, store]
proc logicalHistoryCode(hash: ServicePreimageHash, restore: bool): seq[byte] =
  ## Maintained host26 forget and funded host25 restore consume initialized self/hash/length registers at the actual native invocation slot.
  let raw = array[32, byte](hash)
  var writable = newSeq[byte](32)
  for i in 0..<32: writable[i] = raw[i]
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
      registerImmediate(9, 1), @[10'u8, 26]]
  if restore:
    for instruction in [registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
        registerImmediate(9, 1), @[10'u8, 25]]:
      instructions.add(instruction) # Restore cannot inherit registers overwritten by the preceding host response.
  instructions.add(@[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, writable): result.add(octet)
proc logicalHistoryFixture*(base: OwnedReport, restore: bool): NamespaceExecutionFixture =
  ## Full original code/request/storage declarations enter the parent commitment and signatures before actual Services execution.
  let seeds = namespaceSeeds()
  namespaceExecutionFixture(base, namespaceHaltCode(), logicalHistoryCode(seeds[1].preimages[
      1].hash, restore))
proc checkCollectedHistory*(logical: CurrentLogicalState, hash: ServicePreimageHash,
    restore: bool) =
  ## The original identity stays fixed while literal history slots/bytes come from the actual current logical successor, with retained preimage payload.
  let inventory = logical.currentLogicalInventory.value.suppliedInventory.value
  let request = inventory.inventoryRequestAt(InventoryServiceIndex(1), InventoryRequestIndex(1)).value
  assert array[32, byte](request.hash) == array[32, byte](hash) and uint32(request.length) == 1
  if restore:
    assert request.history.state == RequestState.Reavailable
    assert uint32(request.history.originalFrom) == 1 and uint32(request.history.removedAt) == 2 and
        uint32(request.history.restoredAt) == 2
  else:
    assert request.history.state == RequestState.Unavailable
    assert uint32(request.history.availableFrom) == 1 and uint32(request.history.unavailableFrom) == 2
  let snapshot = logical.logicalProducer.currentUpdateState
  let key = serviceRequestKey(ServiceIndex(99), hash, RequestLength(1), ByteLimit(32)).value
  assert snapshot.lookup(key).value.byteLength == (if restore: 13 else: 9)
  let preimage = servicePreimageKey(ServiceIndex(99), hash, ByteLimit(32)).value
  assert snapshot.lookup(preimage).value.bytes == @[
      77'u8] # Unavailable history alone does not invoke the separate later expunge rule.
