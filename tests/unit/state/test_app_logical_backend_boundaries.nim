# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original backend causes remain distinct across supplied matching, later raw-key capture, targeted review and proof execution; fixed capture remains hash-free.
import std/assertions
import std/syncio
import ../../support/app_collected_native_context
import ../../support/app_collected_supplied_context
import ../../support/state_current_logical_review_context
import ../../support/state_current_logical_proof_context
import ../../../src/app/collected_supplied_plan as app_collected_supplied_plan
import ../../../src/app/collected_supplied_state as app_collected_supplied_state
import ../../../src/app/logical_checkpoint as app_logical_checkpoint
import ../../../src/app/logical_review as app_logical_review
import ../../../src/app/logical_proof as app_logical_proof
import ../../../src/app/proof_query as app_proof_query
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_state as state_current_state
import ../../../src/state/current_review as state_current_review
import ../../../src/state/current_checkpoint as state_current_checkpoint
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/inventory as state_inventory
import ../../../src/state/preimage_content as state_preimage_content
import ../../../src/state/account_review_plan as state_account_review_plan
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/codec/bounded as codec_bounded
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset only the test observer after actual execution and before selected bounded failure boundaries.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Actual complete qualification prefix length independently locates later raw-key revalidation.
proc after(successes: cint) {.importc: "ro_blake_after", cdecl.}
  ## Fail exactly the first primitive after the successful current-state matching prefix.
proc main() {.raises.} =
  ## All source/update/plan authority predates faults; no refused stage can expose a successful output prefix.
  let fixture = collectedNativeFixture()
  let plan = suppliedNativePlan(fixture)
  let logical = suppliedNativeState(fixture)
  let selection = logicalProofPlan()
  let limits = LogicalProofLimits(blocks: ElementLimit(16), viewBytes: ByteLimit(33554432),
      query: logicalProofLimits())
  fail(1)
  let checkpoint = captureLogicalCheckpoint(logical, ByteLimit(1048576))
  assert checkpoint.error == LogicalCheckpointError.None
  let query = captureLogicalProofQuery(logical, selection, limits)
  assert query.error == LogicalProofError.None and calls() == 0
  let supplied = executeCollectedSupplied(fixture.chain, plan, fixture.declarations)
  assert supplied.error == CollectedSuppliedError.StateFailure
  assert supplied.stateFailure.error == CurrentStateError.ManifestFailure
  fail(0)
  let first = qualifyCurrentState(plan.collectedSuppliedGlobals.value, fixture.declarations,
    plan.collectedSuppliedLimits.value.logical.inventory)
  assert first.error == CurrentStateError.None
  let prefix = calls()
  assert prefix > 0 and prefix < 100000
  after(prefix)
  let later = executeCollectedSupplied(fixture.chain, plan, fixture.declarations)
  assert later.error == CollectedSuppliedError.LogicalFailure
  assert later.logicalFailure.error == CurrentLogicalError.LogicalFailure
  assert later.logicalFailure.logicalFailure.error == SuppliedLogicalError.InventoryFailure
  fail(1)
  let reviewed = reviewLogicalState(logical, logicalReviewTestLimits())
  assert reviewed.reviewFailure.error == CurrentReviewError.ExecutionFailure
  assert reviewed.reviewFailure.executionFailure.contentFailure.error ==
      PreimageContentError.BackendFailure
  fail(1)
  let proof = executeProofQuery(query.value)
  assert proof.error == ProofQueryError.ProofFailure and proof.proofError ==
      StateProofError.BackendFailure
  fail(0)
  assert executeCollectedSupplied(fixture.chain, plan, fixture.declarations).error ==
      CollectedSuppliedError.None
  assert executeProofQuery(query.value).error == ProofQueryError.None
  echo "application-logical-backend-boundaries: ok"
try:
  main()
except:
  quit(2) # Ordinary native setup failure cannot impersonate a typed injected backend cause.
