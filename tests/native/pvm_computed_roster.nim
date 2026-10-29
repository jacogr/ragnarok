# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized roster-result guards with genuine epoch-shrink and computed report controls.

import std/[assertions, cmdline]
import ../../src/state/computed/[roster as computed_roster, transition as computed_transition,
    profile as computed_profile]
import ../../src/codec/[assurances, bounded]
import ../../src/codec/state/safrole as state_safrole
import ../support/pvm_computed_roster

proc expect[T](outcome: ComputedRosterResult[T], reason: ComputedRosterError) =
  ## Prove the intended refusal before deliberately extracting its absent application payload.
  assert outcome.error == reason, "computed roster runtime control"
let limits = ComputedRosterLimits(validators: ElementLimit(6), bytes: ByteLimit(2017))
let fixture = rosterFixture(shrink = true, core = 1)
let done = checkComputedRoster(fixture.source, limits)
expect(done, ComputedRosterError.None)
assert uint64(done.value.computedRosterInfo.value.population) == 6
assert uint64(done.value.computedRosterSource.value.computedTransitionSource.value.computedProfileContext.value.validators) == 9
let missing = default(ComputedRosterResult[RosterEligibleComputedReport])
let source = checkComputedRoster(default(TransitionBoundComputedReport), limits)
expect(source, ComputedRosterError.InvalidSource)
let bytes = checkComputedRoster(fixture.source, ComputedRosterLimits(validators: ElementLimit(6),
    bytes: ByteLimit(2016)))
expect(bytes, ComputedRosterError.LimitExceeded)
let count = checkComputedRoster(fixture.source, ComputedRosterLimits(validators: ElementLimit(5),
    bytes: ByteLimit(2017)))
expect(count, ComputedRosterError.LimitExceeded)
let inactive = rosterFixture(shrink = true, core = 2)
let inactiveOutcome = checkComputedRoster(inactive.source, limits)
expect(inactiveOutcome, ComputedRosterError.InactiveCore)
let wrong = rosterFixture(shrink = true, shards = 9)
let shardOutcome = checkComputedRoster(wrong.source, limits)
expect(shardOutcome, ComputedRosterError.WrongErasureShards)
case paramStr(1)
of "default": discard missing.value # Defaults contain no eligible computation.
of "source": discard source.value # No authenticated posterior context.
of "bytes": discard bytes.value # Whole chapter exceeds byte policy.
of "count": discard count.value # Record count exceeds local policy.
of "core": discard inactiveOutcome.value # Parent-active core became inactive.
of "shards": discard shardOutcome.value # Parent shard population is no longer current.
of "owner": discard default(RosterEligibleComputedReport).computedRosterSource.value # No source.
of "active": discard default(RosterEligibleComputedReport).computedRosterActive.value # No records.
else: discard default(RosterEligibleComputedReport).computedRosterInfo.value # No population facts.
