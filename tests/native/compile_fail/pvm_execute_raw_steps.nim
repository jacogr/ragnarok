# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture for bounded-execution metadata privacy and nominal limits.
## Intentionally rejects the forbidden field access or mismatched argument below.

import ../../../src/pvm/[machine, gas, step]
discard execute(default(Machine), 1'u64, GasCycleLimit(1))
