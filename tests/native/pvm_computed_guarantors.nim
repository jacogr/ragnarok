# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized guarantor planning/query guards with genuine epoch-crossing success controls.

import std/assertions
import std/cmdline
import ../../src/state/computed_guarantors as state_computed_guarantors
import ../../src/state/computed_roster as state_computed_roster
import ../../src/state/guarantors as state_guarantors
import ../../src/codec/guarantees as codec_guarantees
import ../../src/codec/bounded as codec_bounded
import ../support/pvm_computed_guarantors

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Cause actual planning provider refusal after signed original inputs complete.
proc expect[T](outcome: ComputedGuarantorResult[T], reason: ComputedGuarantorError) =
  ## Require intended alternatives before deliberate unsuccessful extraction.
  assert outcome.error == reason, "guarantor guard control"
let limits = guarantorLimits()
let source = guarantorFixture(shrink = true)
let planned = prepareComputedGuarantors(source, limits)
expect(planned, ComputedGuarantorError.None)
assert uint64(planned.value.computedGuarantorAt(GuaranteeSlot(8), GuarantorIndex(3)).value.core) == 0
let missing = default(ComputedGuarantorResult[ComputedGuarantors])
let badSource = prepareComputedGuarantors(default(RosterEligibleComputedReport), limits)
expect(badSource, ComputedGuarantorError.InvalidSource)
let invalid = guarantorFixture(rotation = 5)
let configuration = prepareComputedGuarantors(invalid, limits)
expect(configuration, ComputedGuarantorError.InvalidConfig)
var short = limits
short.roster.bytes = ByteLimit(3024)
let boundedOutcome = prepareComputedGuarantors(source, short)
expect(boundedOutcome, ComputedGuarantorError.LimitExceeded)
let slot = planned.value.computedGuarantorAt(GuaranteeSlot(7), GuarantorIndex(3))
expect(slot, ComputedGuarantorError.InvalidSlot)
let index = planned.value.computedGuarantorAt(GuaranteeSlot(12), GuarantorIndex(6))
expect(index, ComputedGuarantorError.InvalidIndex)
let core = planned.value.computedGuarantorAt(GuaranteeSlot(12), GuarantorIndex(0))
expect(core, ComputedGuarantorError.WrongAssignment)
let excludedSource = guarantorFixture(offender = true)
let excluded = prepareComputedGuarantors(excludedSource, limits).value.computedGuarantorAt(
    GuaranteeSlot(2), GuarantorIndex(5))
expect(excluded, ComputedGuarantorError.IneligibleValidator)
reset(1)
let backend = prepareComputedGuarantors(source, limits)
expect(backend, ComputedGuarantorError.BackendFailure)
reset(0)
case paramStr(1)
of "default": discard missing.value # Default has no complete tables.
of "source": discard badSource.value # Missing original eligibility source.
of "config": discard configuration.value # Invalid original rotation profile.
of "limit": discard boundedOutcome.value # Exact prior roster exceeds byte ceiling.
of "slot": discard slot.value # Expired evaluation rotation.
of "index": discard index.value # Current roster has no seventh validator.
of "core": discard core.value # Selected validator belongs to a different core.
of "excluded": discard excluded.value # Cumulative offender was Phi-nullified.
of "backend": discard backend.value # Hash refusal carries no partial tables.
of "owner": discard default(ComputedGuarantors).computedGuarantorSource.value # No retained source.
else: discard default(ComputedGuarantors).computedGuarantorAt(GuaranteeSlot(0), GuarantorIndex(
    0)).value # No default query data.
