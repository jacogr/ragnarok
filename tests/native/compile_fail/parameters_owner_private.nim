# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Parameter snapshots cannot be mutated outside their decoder.
import ../../../src/chain/parameters
var snapshot = default(Parameters)
snapshot.numbers[coreCount] = 3
