# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen actual successor reconstruction preserves namespace identities, detached output isolation and complete current matching.
# @@Verification={"arc":"state_current_refresh_execution_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_refresh_context, parent_globals_context, state_inventory_context,
    supplied_logical_context, arc_evidence]
import ../../../src/state/current/refresh as current_refresh
import ../../../src/state/current/refresh/plan as current_refresh_plan
import ../../../src/state/current/[request_keys as current_request_keys,
    identities as current_identities, profile as current_profile, globals as current_globals,
    state as current_state, logical as current_logical]
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/supplied/logical_inventory as supplied_logical_inventory
import ../../../src/state/[inventory, manifest, store]
import ../../../src/codec/[bounded, report_owned]
import ../../../src/codec/state/[accounts as state_accounts, requests as state_requests,
    composition as state_composition]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Source and request-key derivation finish before observing hash-free execution.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Metadata/history decoding and admitted detached copy-out require no primitive.
proc cycle(plan: CurrentRefreshPlan) =
  ## Retire native output descriptors, empty/nonempty raw keys/payloads and temporary exact codec wires each cycle.
  assert executeCurrentRefresh(plan).value.len == 2
proc main() {.raises.} =
  ## The original complete selected logical parent and actual same-key successor are genuine signed/current outputs.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let keys = namespaceRefreshKeys(decodeOwnedReport(bytes, 2).value)
  let plan = planCurrentRefresh(keys, currentRefreshTestLimits).value
  let update = keys.requestKeysSource.value.identityUpdate.value
  fail(1)
  let result = executeCurrentRefresh(plan)
  assert result.error == CurrentRefreshError.None
  var services = result.value
  assert services.len == 2 and uint32(services[0].service) == 42 and uint32(services[1].service) == 99
  assert services[0].storage[0].key.len == 0 and services[0].storage[0].value.len == 0
  assert services[0].preimages[0].value.len == 0 and services[1].storage[1].value.len == 0
  assert services[0].requests[0].history.state == RequestState.Available
  assert uint32(services[0].metadata.storageItems) == 6 and uint64(services[
      0].metadata.storageBytes) == 236
  services[0].storage[1].key[0] = 255
  services[0].preimages[1].value[0] = 255
  services[0].requests[0].history = requestedHistory()
  services[0].metadata.storageItems = AccountStorageItems(0)
  let fresh = executeCurrentRefresh(plan).value
  assert fresh[0].storage[1].key[0] == 1 and fresh[0].preimages[1].value[0] == 97
  assert fresh[0].requests[0].history.state == RequestState.Available and uint32(fresh[
      0].metadata.storageItems) == 6
  assert executeCurrentRefresh(default(CurrentRefreshPlan)).error == CurrentRefreshError.InvalidPlan
  assert calls() == 0
  for i in 0..<25: cycle(plan)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(plan)
  let after = getOccupiedMem()
  assert before == after and calls() == 0
  recordArcRelease("state_current_refresh_execution", 1000, before, after)
  fail(0)
  let profile = captureCurrentProfile(update, CurrentProfileLimits(validators: ElementLimit(1024),
      bytes: ByteLimit(65536))).value
  let globals = qualifyCurrentGlobals(profile, parentGlobalsTestLimits).value
  let complete = qualifyCurrentState(globals, fresh, inventoryCaptureLimits).value
  let logical = captureCurrentLogicalState(complete, fresh, suppliedLogicalTestLimits).value
  assert sameStateSnapshot(logical.currentLogicalInventory.value.suppliedInventory.value.inventorySource.value.manifestSource.value,
      update.currentUpdateState)
  echo "state-current-refresh-execution: ok"
try:
  main()
except:
  quit(2) # No reconstruction/copy result bypasses actual original/genuine update and whole-map matching.
