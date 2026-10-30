# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit-root restoration prepares complete account reports before any account-content work.
## This synchronous unchanged-format adapter performs no I/O, canonical installation or root discovery.
import ../../codec/state/[trie as state_trie, composition as state_composition]
import ../[validated_checkpoint, inventory]
import ../account/review/plan as account_review_plan
import ../account/review as account_review
import ../economic_profile
type
  PlannedReviewCheckpointLimits* = object ## Restoration, compact capture and complete report preparation keep independent policies.
    serialization*: StateCheckpointLimits
    inventory*: StateInventoryLimits
    review*: AccountReviewPlanLimits
  PlannedReviewCheckpointError* {.pure.} = enum ## Failure exposes only its actual original stage, never an earlier successful owner.
    Uninitialized, None, InvalidProfile, SerializationFailure, InventoryFailure, PreparationFailure, ExecutionFailure
  PlannedReviewCheckpointResult* = object ## Private alternatives preserve complete-only payload authority and guarded nested errors.
    case status: PlannedReviewCheckpointError
    of None:
      completed: StateAccountReview
    of SerializationFailure:
      serializationReason: ValidatedCheckpointResult
    of InventoryFailure:
      inventoryReason: StateInventoryResult[StateInventory]
    of PreparationFailure:
      preparationReason: AccountReviewPlanResult[StateAccountReviewPlan]
    of ExecutionFailure:
      executionReason: AccountReviewExecutionResult
    else:
      discard # Missing policy/default alternatives retain no source or complete review.

func error*(outcome: PlannedReviewCheckpointResult): PlannedReviewCheckpointError =
  ## Inspect the immutable selected stage.
  outcome.status

func value*(outcome: PlannedReviewCheckpointResult): StateAccountReview {.inline,
    requires: outcome.status == PlannedReviewCheckpointError.None.} =
  ## Only fully restored, prepared and executed same-source evidence yields a review.
  outcome.completed

func serializationFailure*(outcome: PlannedReviewCheckpointResult): ValidatedCheckpointResult {.inline,
    requires: outcome.status == PlannedReviewCheckpointError.SerializationFailure.} =
  ## Preserve only the genuine failed serialization stage and its original guarded nested reason.
  outcome.serializationReason

func inventoryFailure*(outcome: PlannedReviewCheckpointResult): StateInventoryResult[
    StateInventory] {.inline, requires: outcome.status ==
    PlannedReviewCheckpointError.InventoryFailure.} =
  ## Preserve only the genuine failed inventory stage and its original guarded nested reason.
  outcome.inventoryReason

func preparationFailure*(outcome: PlannedReviewCheckpointResult): AccountReviewPlanResult[
    StateAccountReviewPlan] {.inline, requires: outcome.status ==
    PlannedReviewCheckpointError.PreparationFailure.} =
  ## Preserve only the genuine failed preparation stage and its original guarded nested reason.
  outcome.preparationReason

func executionFailure*(outcome: PlannedReviewCheckpointResult): AccountReviewExecutionResult {.inline,
    requires: outcome.status == PlannedReviewCheckpointError.ExecutionFailure.} =
  ## Preserve only the genuine failed execution stage and its original guarded nested reason.
  outcome.executionReason

proc decodePlannedReviewCheckpoint*(input: openArray[byte], expected: StateRoot,
    services: openArray[StateService], profile: StateProfile, economics: StateEconomicProfile,
    limits: PlannedReviewCheckpointLimits): PlannedReviewCheckpointResult =
  ## Borrow stable input/declarations only synchronously; root and economic profile are mandatory independent caller selections.
  if economics.economicSchedule.error != EconomicProfileError.None:
    return PlannedReviewCheckpointResult(status: PlannedReviewCheckpointError.InvalidProfile) # Reject missing policy before restoration/capture hashes.
  let serialization = decodeValidatedCheckpoint(input, expected, services, profile,
      limits.serialization)
  if serialization.error != ValidatedCheckpointError.None:
    return PlannedReviewCheckpointResult(status: PlannedReviewCheckpointError.SerializationFailure,
      serializationReason: serialization) # No prefix from an earlier successful phase escapes.
  let inventory = captureStateInventory(serialization.value, services, limits.inventory)
  if inventory.error != StateInventoryError.None:
    return PlannedReviewCheckpointResult(status: PlannedReviewCheckpointError.InventoryFailure,
      inventoryReason: inventory) # No prefix from an earlier successful phase escapes.
  let preparation = planAccountReview(inventory.value, economics, limits.review)
  if preparation.error != AccountReviewPlanError.None:
    return PlannedReviewCheckpointResult(status: PlannedReviewCheckpointError.PreparationFailure,
      preparationReason: preparation) # No prefix from an earlier successful phase escapes.
  let execution = executeAccountReview(preparation.value)
  if execution.error != AccountReviewExecutionError.None:
    return PlannedReviewCheckpointResult(status: PlannedReviewCheckpointError.ExecutionFailure,
      executionReason: execution) # No prefix from an earlier successful phase escapes.
  PlannedReviewCheckpointResult(status: PlannedReviewCheckpointError.None,
      completed: execution.value)
