# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict guarded host logical result extraction with a genuine complete native positive control.
import std/assertions
import std/syncio
import std/cmdline
import std/envvars
import ../../src/app/logical_seed as app_logical_seed
import ../../src/app/collected_update as app_collected_update
import ../../src/app/collected_supplied_plan as app_collected_supplied_plan
import ../../src/app/collected_supplied_state as app_collected_supplied_state
import ../../src/app/logical_checkpoint as app_logical_checkpoint
import ../../src/app/logical_proof as app_logical_proof
import ../../src/app/logical_review as app_logical_review
import ../../src/app/proof_query as app_proof_query
import ../../src/state/parent_logical as state_parent_logical
import ../../src/state/current_logical as state_current_logical
import ../../src/state/current_checkpoint as state_current_checkpoint
import ../../src/state/current_review as state_current_review
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/codec/bounded as codec_bounded
import ../support/app_collected_native_context
import ../support/app_collected_supplied_context
import ../support/state_parent_profile_context
import ../support/state_parent_globals_context
import ../support/codec_supplied_logical_context
import ../support/state_current_logical_proof_context
import ../support/state_current_logical_review_context
proc main() {.raises.} =
  ## Every negative mode must fail at its exact original guard; ordinary source/setup failure never satisfies it.
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  case mode
  of "seed-value":
    let guarded = default(LogicalSeedResult)
    discard guarded.value
  of "seed-profile":
    let guarded = default(LogicalSeedResult)
    discard guarded.profileFailure
  of "seed-globals":
    let guarded = default(LogicalSeedResult)
    discard guarded.globalsFailure
  of "seed-logical":
    let guarded = default(LogicalSeedResult)
    discard guarded.logicalFailure
  of "receipt-value":
    let guarded = default(CollectedUpdateResult)
    discard guarded.value
  of "receipt-preparation":
    let guarded = default(CollectedUpdateResult)
    discard guarded.preparationFailure
  of "plan-value":
    let guarded = default(CollectedSuppliedPlanResult[CollectedSuppliedPlan])
    discard guarded.value
  of "plan-admission":
    let guarded = default(CollectedSuppliedPlanResult[CollectedSuppliedPlan])
    discard guarded.admissionFailure
  of "plan-profile":
    let guarded = default(CollectedSuppliedPlanResult[CollectedSuppliedPlan])
    discard guarded.profileFailure
  of "plan-globals":
    let guarded = default(CollectedSuppliedPlanResult[CollectedSuppliedPlan])
    discard guarded.globalsFailure
  of "supplied-value":
    let guarded = default(CollectedSuppliedResult)
    discard guarded.value
  of "supplied-state":
    let guarded = default(CollectedSuppliedResult)
    discard guarded.stateFailure
  of "supplied-logical":
    let guarded = default(CollectedSuppliedResult)
    discard guarded.logicalFailure
  of "checkpoint-value":
    let guarded = default(LogicalCheckpointResult)
    discard guarded.value
  of "checkpoint-reason":
    let guarded = default(LogicalCheckpointResult)
    discard guarded.checkpointFailure
  of "proof-value":
    let guarded = default(LogicalProofResult)
    discard guarded.value
  of "proof-reason":
    let guarded = default(LogicalProofResult)
    discard guarded.queryFailure
  of "review-value":
    let guarded = default(LogicalReviewResult[ReviewedLogicalState])
    discard guarded.value
  of "review-reason":
    let guarded = default(LogicalReviewResult[ReviewedLogicalState])
    discard guarded.reviewFailure
  of "source-update":
    let source = default(CurrentLogicalState)
    let guarded = source.currentLogicalUpdate
    discard guarded.value
  of "source-context":
    let source = default(CurrentLogicalState)
    let guarded = source.currentLogicalContext
    discard guarded.value
  of "source-view":
    let source = default(CurrentLogicalState)
    let guarded = source.currentLogicalViewInfo
    discard guarded.value
  of "plan-update":
    let source = default(CollectedSuppliedPlan)
    let guarded = source.collectedSuppliedUpdate
    discard guarded.value
  of "plan-global-source":
    let source = default(CollectedSuppliedPlan)
    let guarded = source.collectedSuppliedGlobals
    discard guarded.value
  of "plan-policy":
    let source = default(CollectedSuppliedPlan)
    let guarded = source.collectedSuppliedLimits
    discard guarded.value
  of "pair-logical":
    let source = default(ReviewedLogicalState)
    let guarded = source.reviewedLogicalSource
    discard guarded.value
  of "pair-reviewed":
    let source = default(ReviewedLogicalState)
    let guarded = source.logicalCurrentReview
    discard guarded.value
  else:
    if getEnv("RAGNAROK_STATE_REPORT").len == 0:
      putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # The strict runner starts at the repository root; unit runs retain their explicit absolute fixture binding.
    let fixture = collectedNativeFixture()
    let seedPolicy = LogicalSeedLimits(profile: parentProfileTestLimits,
        globals: parentGlobalsTestLimits, logical: suppliedLogicalTestLimits)
    let seed = captureLogicalSeed(fixture.chain, fixture.fixture.first.services, seedPolicy)
    assert seed.error == LogicalSeedError.None
    discard seed.value.logicalParentInventory.value
    assert captureCollectedUpdate(fixture.chain, fixture.receipt).value.ready
    let plan = planCollectedSupplied(fixture.chain, fixture.receipt, collectedSuppliedTestLimits()).value
    discard plan.collectedSuppliedGlobals.value
    discard plan.collectedSuppliedLimits.value
    let logical = executeCollectedSupplied(fixture.chain, plan, fixture.declarations).value
    discard logical.currentLogicalUpdate.value
    discard logical.currentLogicalContext.value
    discard logical.currentLogicalViewInfo.value
    let capsule = captureLogicalCheckpoint(logical, ByteLimit(1048576)).value
    discard capsule.currentCheckpointInfo.value
    let proofPolicy = LogicalProofLimits(blocks: ElementLimit(16), viewBytes: ByteLimit(33554432),
        query: logicalProofLimits())
    assert captureLogicalProofQuery(logical, logicalProofPlan(), proofPolicy).value.valid
    let pair = reviewLogicalState(logical, logicalReviewTestLimits()).value
    discard pair.reviewedLogicalSource.value
    discard pair.logicalCurrentReview.value
    echo "application-host-logical-controls: ok"
try:
  main()
except:
  quit(2) # Only exact AssertionDefect exits satisfy a registered rejection.
