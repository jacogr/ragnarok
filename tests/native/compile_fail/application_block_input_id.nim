# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## An integer stream identity cannot silently stand in for a reception generation.
# @@Verification={"group": "nominal", "expected": "BlockInputId", "early": ["cancel", "[2] expected: BlockInputId but got: int"]}

import ../../../src/app/block_input
var input = default(BlockInput)
discard input.cancel(1)
