# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original backend causes remain distinct across supplied matching, later raw-key capture, targeted review and proof execution; fixed capture remains hash-free.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_supplied_context,
    current_logical_review_context,
    current_logical_proof_context]
import ../../../src/app/collected/supplied/[plan as collected_supplied_plan,
    state as collected_supplied_state]
import ../../../src/app/logical/[checkpoint as logical_checkpoint, review as logical_review,
    proof as logical_proof]
import ../../../src/app/proof/query as proof_query
import ../../../src/state/current/[logical as current_logical, state as current_state,
    review as current_review, checkpoint as current_checkpoint]
import ../../../src/state/supplied/logical_inventory as supplied_logical_inventory
import ../../../src/state/[manifest, inventory]
import ../../../src/state/preimage/content as preimage_content
import ../../../src/state/account/review/plan as account_review_plan
import ../../../src/state/proof/plan as proof_plan
import ../../../src/state/trie_proof
import ../../../src/codec/bounded
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
