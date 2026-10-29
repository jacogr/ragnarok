# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## New complete authored current fixtures qualify exact parent/successor maps while legacy rollback sentinels remain unchanged.
import std/[assertions, envvars, syncio]
import ../../support/[current_checkpoint_context, current_typed_context,
  accumulation_current_chain_context,
  state_inventory_context, account_review_plan_context]
import ../../../src/state/current/[profile as current_profile, globals as current_globals]
import ../../../src/state/[global_snapshot, manifest, store, inventory]
import ../../../src/state/account/review/plan as account_review_plan
import ../../../src/state/account/review as account_review
import ../../../src/state/economic_profile
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/codec/[bounded, report_owned]
import ../../../src/codec/state/[layout as state_layout, composition as state_composition]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Measure targeted account preparation only after mandatory complete matching/capture hashes.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Empty authored child maps require no account content hashes.
const
  projection = CurrentProfileLimits(validators: ElementLimit(1024), bytes: ByteLimit(65536))
  limits = GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(10000),
      maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))
proc verify(context: CurrentChainFixture) =
  ## The original parent is authored before signing; the successor must match every supplied service row without stripping data.
  let prepared = currentCheckpointPrepared(context)
  let profile = captureCurrentProfile(prepared, projection).value
  let parent = context.parent.value.stateSnapshot
  let original = validateGlobalState(parent, profile.derivedStateProfile.value, limits).value
  assert validateStateManifest(original, currentSuppliedServices(parent),
      inventoryManifestLimits).error == StateManifestError.None
  let source = prepared.currentUpdateState
  let qualified = qualifyCurrentGlobals(profile, limits).value
  let services = currentSuppliedServices(source)
  let manifest = validateStateManifest(qualified.qualifiedGlobals.value, services, inventoryManifestLimits)
  assert manifest.error == StateManifestError.None
  assert source.commitment.entries == 18
  assert source.lookup(chapterKey(StateChapter(250))).error == StateStoreError.MissingKey
  let inventory = captureStateInventory(manifest.value, services, inventoryCaptureLimits).value
  let economics = captureEconomicProfile(profile.derivedParameters.value).value
  fail(1)
  let plan = planAccountReview(inventory, economics, reviewPlanTestLimits).value
  let review = executeAccountReview(plan).value
  assert review.accountReviewInfo.value.invariants.footprints.services == 2
  assert review.accountReviewInfo.value.invariants.content.preimages == 0
  assert review.accountReviewInfo.value.economics.services == 2
  assert sameStateInventory(review.reviewInventory.value, inventory)
  assert calls() == 0
  fail(0)
proc main() {.raises.} =
  ## New mode is opt-in; existing default fixtures still retain their C250 sentinel and refuse complete typed service matching.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  verify(currentChainFixture(base, completeState = true))
  verify(currentChainFixture(base, available = true, completeState = true))
  verify(currentChainFixture(base, available = true, disputed = true, completeState = true))
  verify(currentChainFixture(base, available = true, ticket = true, completeState = true))
  verify(currentChainFixture(base, available = true, rotated = true, completeState = true))
  let old = currentCheckpointPrepared(currentChainFixture(base, available = true))
  let profile = captureCurrentProfile(old, projection).value
  let source = old.currentUpdateState
  assert source.lookup(chapterKey(StateChapter(250))).error == StateStoreError.None
  let globals = qualifyCurrentGlobals(profile, limits).value.qualifiedGlobals.value
  assert validateStateManifest(globals, currentSuppliedServices(source),
      inventoryManifestLimits).error == StateManifestError.MappingMismatch
  echo "state-current-typed-fixture: ok (5 complete cases, legacy control)"
try:
  main()
except:
  quit(2) # Authored input/signature failures cannot qualify complete-map matching or targeted account evidence.
