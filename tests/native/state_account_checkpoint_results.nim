# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic phase guards retain a genuine expected-root restored certificate as their positive control.
import std/[assertions, cmdline, syncio]
import ../support/[state_inventory_context, account_checkpoint_context]
import ../../src/state/account/[checkpoint as account_checkpoint, invariants as account_invariants]
import ../../src/state/[checkpoint, manifest, store]
include ./composition_fixture
proc extract(outcome: AccountCheckpointResult): CheckedAccountInvariants {.noinline.} =
  ## Default restoration has no completed source-bearing certificate.
  outcome.value
proc guardSerialization(outcome: AccountCheckpointResult) {.noinline.} =
  ## A different phase cannot expose the serialization reason.
  discard outcome.serializationFailure
proc guardInventory(outcome: AccountCheckpointResult) {.noinline.} =
  ## A different phase cannot expose the inventory reason.
  discard outcome.inventoryFailure
proc guardFootprint(outcome: AccountCheckpointResult) {.noinline.} =
  ## A different phase cannot expose the footprint reason.
  discard outcome.footprintFailure
proc guardLinkage(outcome: AccountCheckpointResult) {.noinline.} =
  ## A different phase cannot expose the linkage reason.
  discard outcome.linkageFailure
proc guardContent(outcome: AccountCheckpointResult) {.noinline.} =
  ## A different phase cannot expose the content reason.
  discard outcome.contentFailure
proc guardJoin(outcome: AccountCheckpointResult) {.noinline.} =
  ## A different phase cannot expose the join reason.
  discard outcome.joinFailure
case paramStr(1)
of "default": discard extract(default(AccountCheckpointResult)) # No default payload.
of "serialization": guardSerialization(default(AccountCheckpointResult)) # No invented serialization phase.
of "inventory": guardInventory(default(AccountCheckpointResult)) # No invented inventory phase.
of "footprint": guardFootprint(default(AccountCheckpointResult)) # No invented footprint phase.
of "linkage": guardLinkage(default(AccountCheckpointResult)) # No invented linkage phase.
of "content": guardContent(default(AccountCheckpointResult)) # No invented content phase.
of "join": guardJoin(default(AccountCheckpointResult)) # No invented join phase.
of "ok":
  let services = inventoryServices()
  let source = inventoryManifest(compositionFixture(paramStr(2)), services).manifestSource.value
  let wire = encodeFullCheckpoint(source, accountCheckpointLimits.serialization.checkpointBytes).value
  let checked = extract(decodeAccountCheckpoint(wire, source.commitment.root, services,
      inventoryProfile, accountCheckpointLimits))
  assert checked.accountInvariantInfo.value.content.bytes == 3
  echo "state-account-checkpoint-results: ok"
else: quit(2) # Unknown selectors cannot pass controls.
