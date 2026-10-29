# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "got: Gas but wanted: AccumulationReentryDepthLimit"}

## Driver retained depth is a nominal policy, distinct from protocol gas.

import ../../../src/state/accumulation/driver as accumulation_driver
import ../../../src/codec/work/digest as work_digest
discard AccumulationDriverLimits(depth: Gas(4))
