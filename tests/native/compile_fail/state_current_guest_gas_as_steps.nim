# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "got: Gas but wanted: ExecutionStepLimit"}

## Guest work counts cannot alias payload bytes or protocol gas.
import ../../../src/state/accumulation_guest_runner as state_accumulation_guest_runner
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/work_digest as codec_work_digest
discard AccumulationGuestLimits(steps: Gas(1))
