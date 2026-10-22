# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Two mutable receivers cannot share copied callback generations or byte ownership.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <CurrentBlockInput>", "build_name": "current-block-input-copy"}

import ../../../src/app/current_block_input
var original = default(CurrentBlockInput)
var duplicate = original
discard original.cancel(default(CurrentBlockInputId))
discard duplicate.cancel(default(CurrentBlockInputId))
