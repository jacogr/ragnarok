# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Checkpoint, original-current review and proof query owners outlive genuine collected fixture scopes; detached bytes survive all canonical source retirement.
import std/assertions
import std/syncio
import ../../support/app_collected_native_context
import ../../support/app_collected_supplied_context
import ../../support/state_current_logical_review_context
import ../../support/state_current_logical_proof_context
import ../../../src/app/logical_checkpoint as app_logical_checkpoint
import ../../../src/app/logical_review as app_logical_review
import ../../../src/app/logical_proof as app_logical_proof
import ../../../src/app/proof_query as app_proof_query
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_state as state_current_state
import ../../../src/state/current_globals as state_current_globals
import ../../../src/state/current_profile as state_current_profile
import ../../../src/state/current_checkpoint as state_current_checkpoint
import ../../../src/state/current_review as state_current_review
import ../../../src/state/account_review as state_account_review
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/state/planned_proof as state_planned_proof
import ../../../src/state/proof_view as state_proof_view
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/chain/genesis as chain_genesis
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
