# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Checkpoint, original-current review and proof query owners outlive genuine collected fixture scopes; detached bytes survive all canonical source retirement.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_supplied_context,
    current_logical_review_context,
    current_logical_proof_context]
import ../../../src/app/[logical_checkpoint, logical_review, logical_proof, proof_query]
import ../../../src/state/[current_logical, current_state, current_globals, current_profile,
    current_checkpoint, current_review, account_review, checkpoint, proof_plan, planned_proof,
    proof_view, proof_global, store]
import ../../../src/codec/[bounded, state_trie, state_composition]
import ../../../src/chain/genesis
type DetachedConsumers = object ## Only independent bytes, semantic keys, fixed profile and explicitly selected posterior commitment cross the final scope.
  proof, checkpoint: seq[byte]
  plan: StateProofPlan
  root: StateRoot
  profile: StateProfile
proc detached(): DetachedConsumers {.raises.} =
  ## Native fixtures and all logical/current/query/report/capsule owners retire before the caller authenticates detached output.
  let fixture = collectedNativeFixture()
  let logical = suppliedNativeState(fixture)
  let capsule = captureLogicalCheckpoint(logical, ByteLimit(1048576)).value
  let reviewed = reviewLogicalState(logical, logicalReviewTestLimits()).value
  let plan = logicalProofPlan()
  let limits = LogicalProofLimits(blocks: ElementLimit(16), viewBytes: ByteLimit(33554432),
      query: logicalProofLimits())
  let query = captureLogicalProofQuery(logical, plan, limits).value
  let response = executeProofQuery(query).value
  assert reviewed.logicalCurrentReview.value.currentAccountReview.value.accountReviewInfo.value.invariants.content.preimages == 6
  DetachedConsumers(proof: response.bytes(limits.query.wireBytes).value,
    checkpoint: capsule.copyCurrentCheckpoint(ByteLimit(1048576)).value, plan: plan,
    root: logical.currentLogicalContext.value.state.commitment.root,
    profile: logical.currentLogicalSource.value.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedStateProfile.value)
proc main() {.raises.} =
  ## Independent expected roots and schemas are retained before original owners leave scope; response bytes never choose their own trust.
  let outside = detached()
  let limits = logicalProofLimits()
  let view = decodePlannedProofs(outside.proof, outside.plan, outside.root, limits.view,
    limits.proof,
    limits.aggregate, limits.wireBytes).value
  assert uint32(view.readGlobalTime.value) == 2
  let restored = decodeFullCheckpoint(outside.checkpoint, outside.root, genesisStoreLimits(),
      ByteLimit(1048576)).value
  assert array[32, byte](restored.snapshot.value.commitment.root) == array[32, byte](outside.root)
  for i in 1..16:
    assert view.readProofChapter(StateChapterId(i), outside.profile,
      collectedSuppliedTestLimits().globals.chapter).error == GlobalProofError.None
  echo "application-logical-consumer-scopes: ok"
try:
  main()
except:
  quit(2) # Scope retirement cannot fabricate complete state or independently trusted response roots.
