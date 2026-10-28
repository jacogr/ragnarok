# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## An integer stream identity cannot silently stand in for a reception generation.
# @@Verification={"group": "nominal", "expected": "CurrentBlockInputId", "early": ["cancel", "[2] expected: CurrentBlockInputId but got: int"]}

import ../../../src/app/current_block_input as app_current_block_input
var input = default(CurrentBlockInput)
discard input.cancel(1)
