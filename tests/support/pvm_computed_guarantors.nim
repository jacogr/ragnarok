# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored original rotation controls and bounded planning policies for genuine assignment tests.

import std/assertions
import ../../src/state/computed/[guarantors as computed_guarantors, roster as computed_roster]
import ../../src/codec/bounded
import ../../src/codec/state/disputes as state_disputes
import ./pvm_computed_roster

proc guarantorLimits*(): ComputedGuarantorLimits =
  ## Exact maximum previous9 roster extent and one-offender judgment extent, with independent record ceilings.
  ComputedGuarantorLimits(roster: ComputedRosterLimits(validators: ElementLimit(9),
      bytes: ByteLimit(3025)),
    judgments: DisputeStateConfig(perSet: ElementLimit(10), totalItems: ElementLimit(40),
        maxBytes: ByteLimit(36)),
    offenders: ElementLimit(1))
proc guarantorFixture*(shrink = false, core = 0'u64, target = 0'u32,
    offender = false, rotation = 4'u16): RosterEligibleComputedReport =
  ## Capture original rotation before execution and config binding; no posterior result or parameter tuple is forged.
  let fixture = rosterFixture(shrink = shrink, core = core, rotation = rotation, target = target,
      offender = offender)
  let checked = checkComputedRoster(fixture.source, ComputedRosterLimits(validators: ElementLimit(
      9), bytes: ByteLimit(3025)))
  assert checked.error == ComputedRosterError.None, "genuine population-eligible source"
  checked.value
