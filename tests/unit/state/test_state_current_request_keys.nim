# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete current request key derivation is bounded upfront; cached physical identities and aliases remain private/hash-free.
# @@Verification={"arc":"state_current_request_keys_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_request_keys_context, arc_evidence]
import ../../../src/state/[current_request_keys, current_identities, supplied_logical_inventory,
    inventory, manifest, store]
import ../../../src/codec/[bounded, report_owned, state_layout, state_requests]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset primitive observation and optionally refuse key derivation after complete source qualification.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Exactly one maintained key derivation per request belongs to capture; subsequent queries hash nothing.
proc cycle(source: PreservedCurrentIdentities) =
  ## Retire every new native row/key array and source alias without retaining a mutable copy.
  assert captureCurrentRequestKeys(source, currentRequestKeyTestLimits).value.requestKeysInfo.value.requests == 4
proc main() {.raises.} =
  ## Original actual mapping and full current preservation precede primitive/resource observations.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let source = namespacePreservation(decodeOwnedReport(bytes, 2).value)
  let inventory = source.identityLogical.value.suppliedInventory.value
  var expected = default(array[2, array[2, StateKey]])
  for i in 0..<2:
    let service = InventoryServiceIndex(uint64(i))
    let row = inventory.inventoryServiceAt(service).value
    for j in 0..<2:
      let request = inventory.inventoryRequestAt(service, InventoryRequestIndex(uint64(j))).value
      expected[i][j] = serviceRequestKey(row.service, request.hash, request.length, ByteLimit(32)).value
  fail(0)
  let keys = captureCurrentRequestKeys(source, currentRequestKeyTestLimits).value
  assert calls() == 4
  let info = keys.requestKeysInfo.value
  assert info.services == 2 and info.requests == 4
  assert info.bytes == uint64(2*sizeof(seq[StateKey])+4*sizeof(StateKey))
  fail(1)
  for i in 0..<2:
    for j in 0..<2:
      assert array[31, byte](keys.currentRequestKeyAt(InventoryServiceIndex(uint64(i)),
          InventoryRequestIndex(uint64(j))).value) == array[31, byte](expected[i][j])
  assert keys.currentRequestKeyAt(InventoryServiceIndex(high(uint64)), InventoryRequestIndex(
      0)).error == CurrentRequestKeyError.InvalidIndex
  assert keys.currentRequestKeyAt(InventoryServiceIndex(0), InventoryRequestIndex(high(
      uint64))).error == CurrentRequestKeyError.InvalidIndex
  assert keys.currentRequestKeyAt(InventoryServiceIndex(2), InventoryRequestIndex(0)).error ==
      CurrentRequestKeyError.InvalidIndex
  assert keys.currentRequestKeyAt(InventoryServiceIndex(0), InventoryRequestIndex(2)).error ==
      CurrentRequestKeyError.InvalidIndex
  var short = currentRequestKeyTestLimits
  short.services = ElementLimit(1)
  assert captureCurrentRequestKeys(source, short).error == CurrentRequestKeyError.LimitExceeded
  short = currentRequestKeyTestLimits
  short.requests = ElementLimit(3)
  assert captureCurrentRequestKeys(source, short).error == CurrentRequestKeyError.LimitExceeded
  short = currentRequestKeyTestLimits
  short.bytes = ByteLimit(info.bytes-1)
  assert captureCurrentRequestKeys(source, short).error == CurrentRequestKeyError.LimitExceeded
  assert captureCurrentRequestKeys(default(PreservedCurrentIdentities),
      currentRequestKeyTestLimits).error == CurrentRequestKeyError.InvalidSource
  assert calls() == 0
  let failed = captureCurrentRequestKeys(source, currentRequestKeyTestLimits)
  assert failed.error == CurrentRequestKeyError.RequestFailure and failed.requestError ==
      RequestError.BackendFailure and calls() == 1
  fail(0)
  var exact = currentRequestKeyTestLimits
  exact.bytes = ByteLimit(info.bytes)
  assert captureCurrentRequestKeys(source, exact).error == CurrentRequestKeyError.None
  for i in 0..<25: cycle(source)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_current_request_keys", 1000, before, after)
  echo "state-current-request-keys: ok"
try:
  main()
except:
  quit(2) # Actual source/identity/key derivation failures cannot become successful cache evidence.
