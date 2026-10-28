# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent chapter fixtures and complete authenticated source facts test atomic typed proof restoration, root/schema/declaration separation and isolated retained-owner release.
import std/assertions
import std/syncio
import std/envvars
import std/cmdline
import ../support/state_inventory_context
import ../support/codec_supplied_logical_context
import ../support/testing_arc_evidence
import ../../src/state/supplied_proof_import as state_supplied_proof_import
import ../../src/state/proof_state_import as state_proof_state_import
import ../../src/state/proof_view as state_proof_view
import ../../src/state/trie_proof as state_trie_proof
import ../../src/state/snapshot_proof as state_snapshot_proof
import ../../src/state/proof_plan as state_proof_plan
import ../../src/state/planned_proof as state_planned_proof
import ../../src/state/store as state_store
import ../../src/state/global_snapshot as state_global_snapshot
import ../../src/state/manifest as state_manifest
import ../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../src/state/inventory as state_inventory
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_composition as codec_state_composition
import ../../src/codec/state_trie as codec_state_trie
include nimony_composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Genuine complete-root reconstruction cannot succeed through a refusing backend.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Whole import admission and root mismatch refuse before hashing.
const limits = SuppliedProofImportLimits(restoration: ProofStateImportLimits(lookups: ElementLimit(
    64), copyBytes: ByteLimit(1048576), store: StateStoreLimits(trie: inventoryMapLimits,
    writes: ElementLimit(64), writeValueBytes: ByteLimit(262144))), globals: GlobalStateLimits(
    chapter: StateChapterPolicy(items: ElementLimit(1000), maxBytes: ByteLimit(65536)),
    totalBytes: ByteLimit(262144)), logical: suppliedLogicalTestLimits)
const perProof = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(65536))
const aggregate = StateProofBatchLimits(items: ElementLimit(64), nodes: ElementLimit(15936),
    valueBytes: ByteLimit(262144))
const viewLimits = ProofViewLimits(items: ElementLimit(64), valueBytes: ByteLimit(262144))
proc authenticated(source: StateStoreSnapshot): ProofView =
  ## Independently authenticate all exact physical keys through existing proof generation/verification before exercising typed restoration.
  var keys = newSeq[StateKey](source.commitment.entries)
  for i in 0..<keys.len: keys[i] = source.keyAt(state_store.StateEntryIndex(i)).value
  let plan = captureStateProofPlan(keys, ElementLimit(64)).value
  let proofs = generatePlannedProofs(source, plan, inventoryMapLimits, perProof, aggregate).value
  var queries = newSeq[StateProofQuery](proofs.len)
  for i in 0..<queries.len: queries[i] = proofs.queryAt(i).value
  verifyPlannedProofs(plan, queries, source.commitment.root, perProof, aggregate, viewLimits).value
proc restoredSource(source: SuppliedLogicalInventory): StateStoreSnapshot =
  ## Recover only the successful independently owned complete physical source through existing guarded provenance APIs.
  source.suppliedInventory.value.inventorySource.value.manifestSource.value
proc exercise(source: ProofView, root: StateRoot, rows: seq[StateService]) =
  ## One whole success/refusal/recovery cycle retires every new owner before the next isolated ARC measurement boundary.
  let imported = importSuppliedProofState(source, root, inventoryProfile, rows, limits).value
  assert imported.suppliedLogicalInfo.value.services == 2
  assert imported.copySuppliedStorageKey(InventoryServiceIndex(0), InventoryStorageIndex(0),
      ByteLimit(2)).value == @[1'u8, 2]
  var short = limits
  short.logical.keys = ElementLimit(0)
  assert importSuppliedProofState(source, root, inventoryProfile, rows, short).error ==
      SuppliedProofImportError.LogicalFailure
  assert importSuppliedProofState(source, root, inventoryProfile, rows, limits).error ==
      SuppliedProofImportError.None
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(SuppliedProofImportResult)
  if mode == "value":
    discard empty.value
    return
  if mode == "reason":
    discard empty.restorationFailure
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  if mode == "global":
    discard empty.globalFailure
    return
  if mode == "manifest":
    discard empty.manifestFailure
    return
  if mode == "logical":
    discard empty.logicalFailure
    return
  if getEnv("RAGNAROK_COMPOSITION_FIXTURE").len == 0:
    putEnv("RAGNAROK_COMPOSITION_FIXTURE", "build/state11-composition.hex") # The strict control uses the same independently authored chapter fixture as the native suite.
  let chapters = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var rows = inventoryServices()
  let original = inventoryManifest(chapters, rows).manifestSource.value
  let root = original.commitment.root
  let evidence = authenticated(original)
  var malformedStore = forkStateStore(original).value
  let malformed = malformedStore.apply([StateWrite(key: chapterKey(StateChapter(11)), value: @[1'u8])]).value
  let malformedEvidence = authenticated(malformed)
  fail(1)
  assert importSuppliedProofState(default(ProofView), root, inventoryProfile, rows,
      limits).restorationFailure.error == ProofStateImportError.InvalidView and calls() == 0
  assert importSuppliedProofState(evidence, default(StateRoot), inventoryProfile, rows,
      limits).restorationFailure.error == ProofStateImportError.WrongRoot and calls() == 0
  var short = limits
  short.restoration.lookups = ElementLimit(0)
  assert importSuppliedProofState(evidence, root, inventoryProfile, rows,
      short).restorationFailure.error == ProofStateImportError.LimitExceeded and calls() == 0
  let refused = importSuppliedProofState(evidence, root, inventoryProfile, rows, limits)
  assert refused.error == SuppliedProofImportError.RestorationFailure and
      refused.restorationFailure.storeFailure == StateStoreError.BackendFailure
  fail(0)
  let imported = importSuppliedProofState(evidence, root, inventoryProfile, rows, limits).value
  let restored = imported.restoredSource
  assert not sameStateSnapshot(restored, original) and sameStateStorePolicy(restored, original)
  assert restored.commitment.entries == original.commitment.entries
  for i in 0..<original.commitment.entries:
    let key = original.keyAt(state_store.StateEntryIndex(i)).value
    assert restored.lookup(key).value.bytes == original.lookup(
        key).value.bytes # All physical chapters and untouched namespaces remain exact on the independently owned map.
  let partial = projectProofView(evidence, [chapterKey(StateChapter(1))], viewLimits).value
  assert importSuppliedProofState(partial, root, inventoryProfile, rows,
      limits).restorationFailure.error == ProofStateImportError.Incomplete
  let malformedResult = importSuppliedProofState(malformedEvidence, malformed.commitment.root,
      inventoryProfile, rows, limits)
  assert malformedResult.error == SuppliedProofImportError.GlobalFailure
  assert malformedResult.globalFailure.error != GlobalStateError.None # Correct complete-root equality cannot make malformed C(11) a typed time value.
  short = limits
  short.globals.totalBytes = ByteLimit(0)
  assert importSuppliedProofState(evidence, root, inventoryProfile, rows, short).error ==
      SuppliedProofImportError.GlobalFailure
  assert importSuppliedProofState(evidence, root, default(StateProfile), rows, limits).error ==
      SuppliedProofImportError.GlobalFailure
  var omitted = rows
  omitted.setLen(1)
  assert importSuppliedProofState(evidence, root, inventoryProfile, omitted, limits).error ==
      SuppliedProofImportError.ManifestFailure
  var altered = rows
  altered[0].storage[0].value[0] = 88
  assert importSuppliedProofState(evidence, root, inventoryProfile, altered, limits).error ==
      SuppliedProofImportError.ManifestFailure
  short = limits
  short.logical.rawKeyBytes = ByteLimit(1)
  assert importSuppliedProofState(evidence, root, inventoryProfile, rows, short).error ==
      SuppliedProofImportError.LogicalFailure
  var key = imported.copySuppliedStorageKey(InventoryServiceIndex(0), InventoryStorageIndex(0),
      ByteLimit(2)).value
  key[0] = 99
  assert imported.copySuppliedStorageKey(InventoryServiceIndex(0), InventoryStorageIndex(0),
      ByteLimit(2)).value == @[1'u8, 2]
  for i in 0..<25: exercise(evidence, root, rows) # Warm process-local allocator/runtime paths without including native worker ownership.
  let before = getOccupiedMem()
  for i in 0..<1000: exercise(evidence, root, rows) # Failed late raw-key admission must release every restored earlier-stage owner.
  let after = getOccupiedMem()
  assert after == before
  recordArcRelease("state_supplied_proof_import", 1000, before, after)
  echo "state-supplied-proof-import: ok"
try:
  main()
except:
  quit(2) # Ordinary source construction refusal cannot impersonate strict result-access rejection.
