# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject direct access to private fallible host result storage.

import ../../../src/pvm/step

# Test-local failure domain supplies the generic enum parameter.
type Reason = enum
  Refused

let reply = default(HostExecutionResult[Reason])
discard reply.completed
