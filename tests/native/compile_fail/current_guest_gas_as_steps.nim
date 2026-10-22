# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "got: Gas but wanted: ExecutionStepLimit"}

## Guest work counts cannot alias payload bytes or protocol gas.
import ../../../src/state/accumulation_guest_runner
import ../../../src/codec/[bounded, work_digest]
discard AccumulationGuestLimits(steps: Gas(1))
