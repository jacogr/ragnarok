# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Maintained current driver policy for genuine tiny-chain sequence tests.
import ../../src/codec/bounded
import ../../src/state/[accumulation_current_driver, accumulation_current_sequence]
import ./[accumulation_current_round_context, accumulation_current_sequence_context]
proc currentSequenceDriverLimits*(): CurrentSequenceDriverLimits =
  ## Three facts cover the initial round, report-only work and held-transfer execution; terminal inspection needs no fourth slot.
  CurrentSequenceDriverLimits(initial: currentRoundLimits(), planning: currentContinuationLimits(),
    execution: CurrentContinuationExecutionLimits(entries: ElementLimit(3),
        round: currentRoundLimits()))
