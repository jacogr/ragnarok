# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"AccumulationDispatchResult","early":["normalizeAccumulationOutcome(","[1] expected: AccumulationDispatchResult but got: SkippedAccumulation"]}

## A genuine no-execution proof cannot fabricate a completed interpreter outcome.
import ../../../src/state/[accumulation_skip, accumulation_outcome]
discard normalizeAccumulationOutcome(default(SkippedAccumulation))
