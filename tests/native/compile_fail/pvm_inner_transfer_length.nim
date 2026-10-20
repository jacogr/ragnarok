# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject interchange of guest byte lengths and independent local transfer-copy policy.

# @@Verification={"group": "nominal", "expected": "[3] expected: MemoryLength but got: MemoryByteLimit", "early": ["readableRange(", "[3] expected: MemoryLength but got: MemoryByteLimit"]}

import ../../../src/pvm/[inner_machines, machine]
discard readableRange(default(Memory), MemoryAddress(0), MemoryByteLimit(4))
