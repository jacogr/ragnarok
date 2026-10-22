# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic planned-checkpoint payload/phase guards retain genuine expected-root restoration as their control.
import std/[assertions, cmdline, syncio]
import ../support/[state_inventory_context, planned_account_checkpoint_context]
import ../../src/state/[planned_account_checkpoint, account_invariants, checkpoint, manifest, store]
include composition_fixture
proc extract(outcome: PlannedAccountCheckpointResult): CheckedAccountInvariants {.noinline.} =
  ## Default or failed restoration grants no joined source-bearing evidence.
  outcome.value
proc guardSerialization(outcome: PlannedAccountCheckpointResult) {.noinline.} =
  ## Default results have no genuine failed serialization reason.
  discard outcome.serializationFailure
proc guardInventory(outcome: PlannedAccountCheckpointResult) {.noinline.} =
  ## Default results have no genuine failed inventory reason.
  discard outcome.inventoryFailure
proc guardPlanning(outcome: PlannedAccountCheckpointResult) {.noinline.} =
  ## Default results have no genuine failed planning reason.
  discard outcome.planningFailure
proc guardAudit(outcome: PlannedAccountCheckpointResult) {.noinline.} =
  ## Default results have no genuine failed audit reason.
  discard outcome.auditFailure
case paramStr(1)
of "default": discard extract(default(PlannedAccountCheckpointResult)) # No default payload.
of "serialization": guardSerialization(default(PlannedAccountCheckpointResult)) # No invented phase.
of "inventory": guardInventory(default(PlannedAccountCheckpointResult)) # No invented phase.
of "planning": guardPlanning(default(PlannedAccountCheckpointResult)) # No invented phase.
of "audit": guardAudit(default(PlannedAccountCheckpointResult)) # No invented phase.
of "ok":
  let services = inventoryServices()
  let source = inventoryManifest(compositionFixture(paramStr(2)), services).manifestSource.value
  let wire = encodeFullCheckpoint(source, plannedCheckpointTestLimits.serialization.checkpointBytes).value
  let checked = extract(decodePlannedAccountCheckpoint(wire, source.commitment.root, services,
      inventoryProfile, plannedCheckpointTestLimits))
  assert checked.accountInvariantInfo.value.content.bytes == 3
  echo "state-planned-account-checkpoint-results: ok"
else: quit(2) # Unknown selectors cannot satisfy controls.
