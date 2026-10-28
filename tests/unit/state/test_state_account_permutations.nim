# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Declaration permutations preserve complete mapping/root/checkpoint bytes while never substituting logical owner identity.
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_inventory_context
import ../../support/state_planned_account_checkpoint_context
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/store as state_store
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/planned_account_checkpoint as state_planned_account_checkpoint
import ../../../src/state/account_audit_plan as state_account_audit_plan
import ../../../src/state/account_audit as state_account_audit
import ../../../src/state/account_invariants as state_account_invariants
import ../../../src/state/footprint_audit as state_footprint_audit
import ../../../src/state/preimage_content as state_preimage_content
import ../../../src/state/preimage_linkage as state_preimage_linkage
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_requests as codec_state_requests
include ../../native/nimony_composition_fixture
const auditLimits = AccountAuditLimits(planning: ElementLimit(64),
  footprints: FootprintAuditLimits(services: ElementLimit(4), checks: ElementLimit(64)),
  content: PreimageContentLimits(services: ElementLimit(4), preimages: ElementLimit(4),
      perValue: ByteLimit(3), totalBytes: ByteLimit(12)),
  linkage: PreimageLinkageLimits(services: ElementLimit(4), preimages: ElementLimit(4),
      comparisons: ElementLimit(8)))
proc declarations(): seq[StateService] =
  ## Lower fixture facts use two storage keys and two request lengths with independently authored 6-item/238-octet metadata.
  let base = inventoryServices()[0]
  result = @[]
  for i in 0..<4:
    var metadata = base.metadata
    metadata.storageItems = AccountStorageItems(6)
    metadata.storageBytes = AccountStorageBytes(238)
    result.add(StateService(service: ServiceIndex(uint32(7+i)), metadata: metadata,
      storage: @[StateStorageItem(key: @[byte(1), 2], value: @[byte(3)]), StateStorageItem(key: @[
          byte(4)], value: @[])],
      preimages: base.preimages, requests: @[base.requests[0], StateRequestItem(
          hash: base.preimages[0].hash,
        length: RequestLength(1), history: requestedHistory())]))
proc permutation(rank: int): array[4, int] =
  ## Factoradic selection enumerates every unique order without in-place aliased swaps.
  result = default(array[4, int])
  var remainder = rank
  var used = default(array[4, bool])
  for position in 0..<4:
    let factor = if position == 0: 6 elif position == 1: 2 else: 1
    var choice = remainder div factor
    remainder = remainder mod factor
    for candidate in 0..<4:
      if not used[candidate]:
        if choice == 0:
          result[position] = candidate
          used[candidate] = true
          break # Every remaining identity is chosen once at this sorted rank.
        choice -= 1
proc check(fixture: seq[seq[byte]], original: StateInventory, wire: seq[byte], rank: int) =
  ## Vary service, storage and request declaration order while preserving every exact logical byte/value.
  let base = declarations()
  var services: seq[StateService] = @[]
  for index in permutation(rank):
    let item = base[index]
    services.add(StateService(service: item.service, metadata: item.metadata,
      storage: (if rank mod 2 == 0: @[item.storage[1], item.storage[0]] else: item.storage),
      preimages: item.preimages, requests: (if rank mod 3 == 0: @[item.requests[1], item.requests[
          0]] else: item.requests)))
  let manifest = inventoryManifest(fixture, services)
  let source = captureStateInventory(manifest, services, inventoryCaptureLimits).value
  assert not sameStateInventory(source, original)
  let snapshot = manifest.manifestSource.value
  let expected = original.inventorySource.value.manifestSource.value.commitment.root
  assert array[32, byte](snapshot.commitment.root) == array[32, byte](expected)
  assert encodeFullCheckpoint(snapshot, plannedCheckpointTestLimits.serialization.checkpointBytes).value == wire
  let completed = executeAccountAudit(planAccountAudit(source, auditLimits).value).value
  assert sameStateInventory(completed.accountInvariantInventory.value, source)
  let oldFootprints = auditAccountFootprints(original, auditLimits.footprints).value
  let content = auditPreimageContent(source, auditLimits.content).value
  let linkage = auditPreimageLinkage(source, auditLimits.linkage).value
  assert joinAccountInvariants(oldFootprints, content, linkage).error ==
      AccountInvariantError.SourceMismatch
  var limits = plannedCheckpointTestLimits
  limits.audit = auditLimits
  let restored = decodePlannedAccountCheckpoint(wire, expected, services, inventoryProfile, limits)
  assert restored.error == PlannedAccountCheckpointError.None
  assert restored.value.accountInvariantInfo.value.content.preimages == 4
proc main() {.raises.} =
  ## Twenty-four service permutations also vary child orders under one canonical complete root and transport envelope.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  let services = declarations()
  let manifest = inventoryManifest(fixture, services)
  let source = captureStateInventory(manifest, services, inventoryCaptureLimits).value
  let wire = encodeFullCheckpoint(manifest.manifestSource.value,
      plannedCheckpointTestLimits.serialization.checkpointBytes).value
  for rank in 0..<24:
    check(fixture, source, wire, rank) # Release each independently captured/restored graph before the next order.
  echo "state-account-permutations: ok (24 cases)"
try:
  main()
except:
  quit(2) # Fixture failure cannot qualify canonical mapping or owner-separation evidence.
