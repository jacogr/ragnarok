# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Two mutable receivers cannot share copied callback generations or byte ownership.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <BlockInput>", "build_name": "application-block-input-copy"}

import ../../../src/app/block_input
var original = default(BlockInput)
var duplicate = original
discard original.cancel(default(BlockInputId))
discard duplicate.cancel(default(BlockInputId))
