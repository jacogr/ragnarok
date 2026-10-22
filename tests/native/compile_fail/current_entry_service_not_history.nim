# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: CurrentSequenceEntryIndex but got: InvocationServiceIndex"}

## Later execution accepts genuine plan authority and local policy, never replacement frame/price/index domains.
import ../../../src/state/accumulation_inputs
import ../../../src/state/accumulation_current_sequence
discard currentSequenceCoverageAt(default(CurrentAccumulationSequence), InvocationServiceIndex(0))
