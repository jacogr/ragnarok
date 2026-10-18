# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject bypasses of private ownership/results or nominal address/resource domains.
import ../../../src/pvm/machine
var outcome = default(MachineResult[Memory])
outcome.status = MachineError.None
