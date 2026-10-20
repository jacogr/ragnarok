# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject interchange of guest byte lengths and independent local transfer-copy policy.

# @@Verification={"group": "nominal", "expected": "[5] expected: MemoryByteLimit but got: MemoryLength", "early": ["innerPeekResponse(", "[5] expected: MemoryByteLimit but got: MemoryLength"]}

import ../../../src/pvm/[inner_machines, machine]
discard innerPeekResponse(default(InnerMachines), MachineGas(0), default(RegisterFile),
  default(Memory), MemoryLength(4))
