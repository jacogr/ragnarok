# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict publication refusals and retained receipt accessors with a real successful computed publication control.

import std/[assertions, cmdline]
import ../../src/state/computed/state/publication as computed_state_publication
import ../../src/state/computed/composition as computed_composition
import "../../src/state/accumulation/block/publication" as accumulation_block_publication
import ../../src/state/store
import ../support/pvm_computed_state_publication

proc expect[T](outcome: ComputedStatePublicationResult[T], reason: ComputedStatePublicationError) =
  ## Validate exact selection without turning intended runtime misuse into a compile-time contradiction.
  assert outcome.error == reason, "computed publication runtime control"
let source = statePublicationFixture()
var target = forkStateStore(source.statePublicationParent).value
let done = publishComputedState(target, source)
expect(done, ComputedStatePublicationError.None)
assert sameStateSnapshot(done.value.computedPublishedSnapshot.value, target.snapshot.value)
let stale = publishComputedState(target, source)
expect(stale, ComputedStatePublicationError.PublicationFailure)
assert stale.publicationFailure.error == AccumulationPublicationError.StaleState
var empty = default(StateStore)
let missingTarget = publishComputedState(empty, source)
expect(missingTarget, ComputedStatePublicationError.PublicationFailure)
assert missingTarget.publicationFailure.stateError == StateStoreError.Uninitialized
let invalid = publishComputedState(target, default(ComposedComputedState))
expect(invalid, ComputedStatePublicationError.InvalidSource)
let missing = default(ComputedStatePublicationResult[PublishedComputedState])
case paramStr(1)
of "default": discard missing.value # Default has no receipt.
of "source": discard invalid.value # Invalid composition grants no publication.
of "stale": discard stale.value # Wrong parent/replay carries no successful snapshot.
of "target": discard missingTarget.value # Uninitialized store cannot be adopted.
of "owner": discard default(PublishedComputedState).computedPublishedSource.value # Empty receipt has no original authority.
of "snapshot": discard default(PublishedComputedState).computedPublishedSnapshot.value # Empty receipt owns no map.
of "reason-default": discard missing.publicationFailure # No child refusal selected.
of "reason-success": discard done.publicationFailure # Success retains no unrelated refusal.
else: discard invalid.publicationFailure # Invalid composition has no child phase.
