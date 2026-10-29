# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict selected-success probes for skipped accumulation outcomes and retained source certificates.
## Dynamic execution must fail at the contract rather than expose default state or zero-effect success.

import std/cmdline
import ../../src/state/accumulation/[skip as accumulation_skip, service as accumulation_service]

# Keep a real refused-result factory path without constant-invalid extraction during compilation.
let outcome = if paramStr(1) == "refused":
  finishUninvokedAccumulation(default(PreparedAccumulationService))
else: default(AccumulationSkipResult[SkippedAccumulation]) # Default outcomes contain no successful payload.
let owner = default(SkippedAccumulation)
let bound = default(BlockSkippedAccumulation)
case paramStr(1)
of "info": discard owner.skipInfo.value # Invalid provenance cannot supply a completed outcome.
of "state": discard owner.skipState.value # Invalid provenance cannot supply a completed outcome.
of "service": discard owner.skipService.value # Invalid provenance cannot supply a completed outcome.
of "projection": discard bound.skipProjection.value # Invalid provenance cannot supply a completed outcome.
of "source": discard bound.skipBlockService.value # Invalid provenance cannot supply a completed outcome.
of "bound-refused": discard finishBlockUninvokedAccumulation(default(
    BlockAccumulationService)).value # Invalid provenance cannot supply a completed outcome.
else: discard outcome.value # Actual/default refusal cannot fabricate unchanged-state success.
