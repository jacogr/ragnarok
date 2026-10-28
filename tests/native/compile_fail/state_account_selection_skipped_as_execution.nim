# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"AccumulationDispatchResult","early":["normalizeAccumulationOutcome(","[1] expected: AccumulationDispatchResult but got: SkippedAccumulation"]}

## A genuine no-execution proof cannot fabricate a completed interpreter outcome.
import ../../../src/state/accumulation_skip as state_accumulation_skip
import ../../../src/state/accumulation_outcome as state_accumulation_outcome
discard normalizeAccumulationOutcome(default(SkippedAccumulation))
