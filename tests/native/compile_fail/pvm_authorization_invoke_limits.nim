# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject authorization result forgery, source/CPU replacement and mixed independent local policy domains.

# @@Verification={"group": "nominal", "expected": "got: MemoryByteLimit but wanted: OutputByteLimit"}

import ../../../src/state/authorization_invocation as state_authorization_invocation
import ../../../src/pvm/machine as pvm_machine
discard AuthorizationInvocationLimits(output: MemoryByteLimit(1))
