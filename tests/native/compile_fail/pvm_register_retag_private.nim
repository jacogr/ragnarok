# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject bypasses of the selected register-result alternative.
import ../../../src/pvm/registers
var r = default(RegisterResult)
r.status = RegisterError.None
