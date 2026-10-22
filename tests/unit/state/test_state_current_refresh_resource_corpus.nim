# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual complete namespace shapes independently qualify exact output ledgers, present-empty facts and high-domain policy arithmetic.
# @@Verification={"arc":"state_current_refresh_resource_corpus_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_namespace_transition_context, current_namespace_execution_context,
    current_namespace_context, current_namespace_refresh_context, service_namespace_seed,
    accumulation_execution_context, supplied_services_context, arc_evidence]
import ../../../src/state/[current_identities, current_request_keys, current_refresh_plan,
    current_logical_refresh, current_logical, supplied_logical_inventory, supplied_services,
    inventory, manifest, store, accumulation_current_update]
import ../../../src/codec/[bounded, report_owned, state_accounts, state_composition,
    state_service_values, state_requests]
import ../../../src/crypto/primitives
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Every actual original/current source and cached request key precedes independent hash-free copy admission.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Policy ledgers and resource refusals inspect only fixed facts/cached extents.
proc seeds(mode: int): seq[ServiceNamespaceSeed] =
  ## Five bounded authored shapes cover no children, present-empty namespaces, ordinary mixed data,65-byte keys/values and several storage rows.
  if mode == 2: return namespaceSeeds()
  result = @[]
  for id in [42'u32, 99'u32]:
    var seed = ServiceNamespaceSeed(service: ServiceIndex(id), storage: @[], preimages: @[],
        requests: @[])
    if mode == 1:
      let hash = ServicePreimageHash(array[32, byte](blake2b256([]).value))
      seed.storage = @[StateStorageItem(key: @[], value: @[])]
      seed.preimages = @[StatePreimageItem(hash: hash, value: @[])]
      seed.requests = @[StateRequestItem(hash: hash, length: RequestLength(0),
          history: availableHistory(RequestSlot(1)))]
    elif mode == 3:
      var key = newSeq[byte](65)
      var value = newSeq[byte](65)
      for i in 0..<65:
        key[i] = byte(i+1)
        value[i] = byte(200-i) # Complete tiny byte ranges prove fixture arithmetic without narrowing/wrapping.
      seed.storage = @[StateStorageItem(key: key, value: value)]
    elif mode == 4:
      for i in 0..<4:
        seed.storage.add(StateStorageItem(key: @[byte(i)], value: newSeq[byte](
            i))) # Several distinct identities include a present-empty value.
      let empty = ServicePreimageHash(array[32, byte](blake2b256([]).value))
      let hash = ServicePreimageHash(array[32, byte](blake2b256([97'u8, 98, 99]).value))
      seed.preimages = @[StatePreimageItem(hash: empty, value: @[]), StatePreimageItem(hash: hash,
          value: @[97'u8, 98, 99])]
      seed.requests = @[StateRequestItem(hash: empty, length: RequestLength(0),
          history: availableHistory(RequestSlot(1))), StateRequestItem(hash: hash,
          length: RequestLength(3), history: availableHistory(RequestSlot(1)))]
    result.add(seed)
proc cycle(plans: openArray[CurrentLogicalRefreshPlan]) =
  ## Retire genuine complete captures and detached descriptors/payloads across all independently authored shape boundaries.
  for plan in plans:
    let logical = executeCurrentLogicalRefresh(plan).value
    assert copySuppliedServices(logical.currentLogicalInventory.value,
        suppliedServicesTestLimits).value.len == 2
proc main() {.raises.} =
  ## Missing code selects genuine zero-gas skips; no mutable post-map or fake current completion supplies the corpus.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  assert sizeof(StateService) < 4096 and sizeof(StateStorageItem) < 4096 and sizeof(
      StatePreimageItem) < 4096 and sizeof(StateRequestItem) < 4096
  var plans: seq[CurrentLogicalRefreshPlan] = @[]
  for mode in 0..<5:
    var options = executionFixtureConfig()
    options.first = ExecutionEnding.Missing
    options.second = ExecutionEnding.Missing
    options.firstProgram = namespaceHaltCode()
    options.secondProgram = options.firstProgram
    options.signed.serviceNamespaces = seeds(mode)
    let fixture = namespaceTransitionFixture(base, options)
    let stages = namespaceRefreshStages(fixture)
    var facts = 2'u64
    var copied = 2'u64*uint64(sizeof(StateService))
    var wire = 210'u64
    var rawBytes = 0'u64
    var storageBytes = 0'u64
    var preimageBytes = 0'u64
    var maximum = 0'u64
    for service in fixture.services:
      assert service.storage.len <= 4 and service.preimages.len <= 2 and service.requests.len <= 2
      facts+=uint64(service.storage.len+service.preimages.len+service.requests.len)
      copied+=uint64(service.storage.len)*uint64(sizeof(StateStorageItem))+uint64(
          service.preimages.len)*uint64(sizeof(StatePreimageItem))+uint64(
          service.requests.len)*uint64(sizeof(StateRequestItem))
      for item in service.storage:
        assert item.key.len <= 65 and item.value.len <= 65
        rawBytes+=uint64(item.key.len)
        storageBytes+=uint64(item.value.len)
        maximum = max(maximum, max(uint64(item.key.len), uint64(item.value.len)))
      for item in service.preimages:
        assert item.value.len <= 65
        preimageBytes+=uint64(item.value.len)
        maximum = max(maximum, uint64(item.value.len))
      for item in service.requests:
        assert item.history.state == RequestState.Available
        wire+=5 # Authored one-slot histories have one count plus one E4, independent of production admission bookkeeping.
    copied+=rawBytes+storageBytes+preimageBytes # Declared tiny counts/sizes bound this independent sum far below the native range.
    fail(1)
    let info = stages.reconstruction.refreshPlanInfo.value
    assert info.facts == facts and info.checks == facts and info.bytes == copied and
        info.wireBytes == wire
    assert info.rawKeyBytes == rawBytes and info.storageBytes == storageBytes and
        info.preimageBytes == preimageBytes
    var exact = namespaceRefreshLimits
    exact.projection.services = ElementLimit(2)
    exact.projection.facts = ElementLimit(facts)
    exact.projection.bytes = ByteLimit(copied)
    exact.projection.perValue = ByteLimit(maximum)
    exact.checks = ElementLimit(facts)
    exact.wireBytes = ByteLimit(wire)
    assert planCurrentRefresh(stages.keys, exact).error == CurrentRefreshPlanError.None
    var short = exact
    short.projection.bytes = ByteLimit(copied-1)
    assert planCurrentRefresh(stages.keys, short).refusedPhase == CurrentRefreshRefusal.Projection
    short = exact
    short.wireBytes = ByteLimit(wire-1)
    assert planCurrentRefresh(stages.keys, short).refusedPhase == CurrentRefreshRefusal.Wire
    short = exact
    short.checks = ElementLimit(facts-1)
    assert planCurrentRefresh(stages.keys, short).refusedPhase == CurrentRefreshRefusal.Planning
    if maximum > 0:
      short = exact
      short.projection.perValue = ByteLimit(maximum-1)
      assert planCurrentRefresh(stages.keys, short).refusedPhase == CurrentRefreshRefusal.Projection
    var huge = exact
    huge.projection.services = ElementLimit(high(uint64))
    huge.projection.facts = ElementLimit(high(uint64))
    huge.projection.bytes = ByteLimit(high(uint64))
    huge.projection.perValue = ByteLimit(high(uint64))
    huge.checks = ElementLimit(high(uint64))
    huge.wireBytes = ByteLimit(high(uint64))
    assert planCurrentRefresh(stages.keys, huge).value.refreshPlanInfo.value.bytes == copied
    assert calls() == 0
    fail(0)
    let logical = executeCurrentLogicalRefresh(stages.complete).value
    let inventory = logical.currentLogicalInventory.value.suppliedInventory.value
    assert inventory.inventorySource.value.manifestInfo.value.entries == 16+int(facts)
    assert sameStateSnapshot(inventory.inventorySource.value.manifestSource.value,
        fixture.update.currentUpdateState)
    plans.add(stages.complete)
  for i in 0..<25: cycle(plans)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(plans)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_current_refresh_resource_corpus", 1000, before, finalBytes)
  echo "state-current-refresh-resource-corpus: ok"
try:
  main()
except:
  quit(2) # Independent authored shapes and genuine current map matching must agree before any resource/ARC corpus verdict.
