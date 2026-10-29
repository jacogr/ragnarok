# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CompletedBlockAccumulation", "early": ["driveAccumulation(", "[1] expected: CompletedBlockAccumulation but got: StateStoreSnapshot"]}

## Only genuine initial completion can authorize this driver.

import ../../../src/state/accumulation/driver as accumulation_driver
import ../../../src/state/store
import ../../../src/chain/parameters
var source: StateStoreSnapshot
discard driveAccumulation(source, default(Parameters), default(AccumulationDriverLimits))
