# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete current-pin shape matrices exercise inventory capture, frozen admission and all account predicates together.
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_inventory_context
import ../../../src/state/inventory as state_inventory
import ../../../src/state/account_audit_plan as state_account_audit_plan
import ../../../src/state/account_audit as state_account_audit
import ../../../src/state/account_invariants as state_account_invariants
import ../../../src/state/footprint_audit as state_footprint_audit
import ../../../src/state/preimage_content as state_preimage_content
import ../../../src/state/preimage_linkage as state_preimage_linkage
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_requests as codec_state_requests
include ../../native/nimony_composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset hash counters or refuse all account content work after source capture.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Early dependent-field failures must not reach content hashing.
const limits = AccountAuditLimits(planning: ElementLimit(64),
  footprints: FootprintAuditLimits(services: ElementLimit(4), checks: ElementLimit(64)),
  content: PreimageContentLimits(services: ElementLimit(4), preimages: ElementLimit(8),
      perValue: ByteLimit(3), totalBytes: ByteLimit(24)),
  linkage: PreimageLinkageLimits(services: ElementLimit(4), preimages: ElementLimit(8),
      comparisons: ElementLimit(16)))
proc shape(index: int): seq[StateService] =
  ## Independently construct small exact shapes using literal preimage digests and direct safe footprint equations.
  let emptyHash = ServicePreimageHash([byte(0x0e), byte(0x57), byte(0x51), byte(0xc0), byte(0x26),
      byte(0xe5), byte(0x43), byte(0xb2), byte(0xe8), byte(0xab), byte(0x2e), byte(0xb0), byte(
      0x60), byte(0x99), byte(0xda), byte(0xa1), byte(0xd1), byte(0xe5), byte(0xdf), byte(0x47),
      byte(0x77), byte(0x8f), byte(0x77), byte(0x87), byte(0xfa), byte(0xab), byte(0x45), byte(
      0xcd), byte(0xf1), byte(0x2f), byte(0xe3), byte(0xa8)])
  let abc = inventoryServices()[0].preimages[0]
  result = @[]
  for service in 0..<(1+index mod 4):
    let id = ServiceIndex(uint32(100+service))
    var row = StateService(service: id, metadata: ServiceMetadata(balance: AccountBalance(1000),
      supervisor: id, supervisorCreated: AccountSlot(2), created: AccountSlot(2)))
    var storageBytes = 0'u64
    for key in 0..<((index+service) mod 4):
      let size = (index+key) mod 3
      var value = newSeq[byte](size)
      for k in 0..<size: value[k] = byte(k+1) # Deterministic independent raw storage values include empty values.
      row.storage.add(StateStorageItem(key: @[byte(key), byte(index)], value: value))
      storageBytes += uint64(36+size) # Two raw key bytes plus fixed34 overhead, safe small integer reference.
    let count = (index+service) mod 3
    if count >= 1:
      row.preimages.add(StatePreimageItem(hash: emptyHash, value: @[]))
      row.requests.add(StateRequestItem(hash: emptyHash, length: RequestLength(0),
          history: availableHistory(RequestSlot(3)))) # Present-empty counts as a real preimage and request.
    if count >= 2:
      row.preimages.add(abc)
      row.requests.add(StateRequestItem(hash: abc.hash, length: RequestLength(3),
          history: availableHistory(RequestSlot(
          3)))) # Literal abc hash remains independent of production hashing.
    let storageCount = row.storage.len
    row.metadata.storageItems = AccountStorageItems(uint32(storageCount+2*count))
    row.metadata.storageBytes = AccountStorageBytes(storageBytes+uint64(81*count)+(if count ==
        2: 3'u64 else: 0'u64))
    result.add(row)
proc check(fixture: seq[seq[byte]], index: int) =
  ## Full lower-encoded map provenance survives varied rows, empty values and targeted semantic mutations.
  var services = shape(index)
  let source = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  let plan = planAccountAudit(source, limits).value
  fail(0)
  let completed = executeAccountAudit(plan)
  assert completed.error == AccountAuditError.None
  assert uint64(calls()) == plan.accountPlanInfo.value.preimages
  assert sameStateInventory(completed.value.accountInvariantInventory.value, source)
  assert completed.value.accountInvariantInfo.value.footprints.services == services.len
  fail(0)
  let originalItems = uint32(services[0].metadata.storageItems)
  services[0].metadata.storageItems = AccountStorageItems(originalItems+1)
  let wrong = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  fail(1)
  let refused = executeAccountAudit(planAccountAudit(wrong, limits).value)
  assert refused.error == AccountAuditError.FootprintFailure
  assert refused.footprintFailure.error == FootprintAuditError.ItemsMismatch and calls() == 0
  fail(0)
proc main() {.raises.} =
  ## Ninety-six complete maps span every small row/storage/preimage combination repeatedly with distinct raw keys.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  for index in 0..<96:
    check(fixture, index) # Each case retires complete owner graphs and its deliberately invalid source locally.
  echo "state-account-matrix: ok (96 cases)"
try:
  main()
except:
  quit(2) # Fixture/observer setup failure cannot qualify the integration matrix.
