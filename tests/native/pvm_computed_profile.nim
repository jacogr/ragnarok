# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized configured-profile and fixed-context projection guards with genuine full parent/map controls.

import std/[assertions, cmdline]
import ../../src/state/[computed_profile, computed_lookup, store]
import ../../src/chain/[genesis, parameters]
import ../support/[pvm_computed_profile, pvm_computed_lookup, pvm_computed_lookup_vectors, pvm_computed_state]

proc check[T](outcome: ComputedProfileResult[T], reason: ComputedProfileError) =
  ## Confirm selected alternatives before deliberate unsuccessful extraction.
  assert outcome.error == reason, "computed profile guard control"
proc refusedProjection(mode: string): BlockSnapshotResult {.noinline.} =
  ## Keep failed context selection dynamic so the runtime contract is tested beyond compile-time variant rejection.
  if mode == "projection": return unavailableGenesis() # Absent/default alternative.
  invalidGenesis() # Known invalid capture alternative.
let rejectedProjection = refusedProjection(paramStr(1))
assert rejectedProjection.error != GenesisError.None, "dynamic failed projection control"
let fixture = profileFixture()
let done = bindComputedProfile(fixture.source, fixture.configured)
check(done, ComputedProfileError.None)
assert array[32, byte](done.value.computedProfileContext.value.hash) == ParentHash, "independent full sealed-parent control"
assert sameStateSnapshot(done.value.computedProfileContext.value.state,
    fixture.state.snapshot.value), "exact original map control"
let missing = default(ComputedProfileResult[ConfiguredComputedReport])
let source = bindComputedProfile(default(LookupAnchoredComputedReport), fixture.configured)
check(source, ComputedProfileError.InvalidSource)
let context = bindComputedProfile(fixture.source, default(BlockSnapshotResult))
check(context, ComputedProfileError.InvalidContext)
let clone = clonedState(fixture.state.snapshot.value)
let foreignState = captureBlockSnapshot(lookupWire(fixture.parent), clone.snapshot.value,
    fixture.parameters)
let state = bindComputedProfile(fixture.source, foreignState)
check(state, ComputedProfileError.StateMismatch)
let other = alteredLookupHeader(fixture.parent, 201, 44)
let foreignParent = captureBlockSnapshot(lookupWire(other), fixture.state.snapshot.value,
    fixture.parameters)
let parent = bindComputedProfile(fixture.source, foreignParent)
check(parent, ComputedProfileError.ParentMismatch)
let alternate = captureBlockSnapshot(lookupWire(fixture.parent), fixture.state.snapshot.value,
    changedParameter(fixture.parameters, depositPerItem))
let parameterFailure = bindComputedProfile(fixture.source, alternate)
check(parameterFailure, ComputedProfileError.ParameterMismatch)
case paramStr(1)
of "default": discard missing.value # Defaults contain no configured computation.
of "source": discard source.value # No anchored original execution provenance.
of "context": discard context.value # No completed configured parent snapshot.
of "state": discard state.value # Equal roots cannot replace exact original map identity.
of "parent": discard parent.value # Same state/config cannot replace the sealed parent.
of "parameters": discard parameterFailure.value # Matching core/epoch alone is insufficient.
of "owner": discard default(ConfiguredComputedReport).computedProfileSource.value # Defaults have no source.
of "facts": discard default(ConfiguredComputedReport).computedProfileContext.value # Defaults have no projected context.
of "projection": discard rejectedProjection.blockSnapshotContext # Guarded projection cannot expose uninitialized storage.
else: discard rejectedProjection.blockSnapshotContext # A known failed capture cannot project context facts.
