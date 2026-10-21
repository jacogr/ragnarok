# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual ARC lowering must reject a second implicit prepared-envelope owner.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <PreparedApplicationCheckpoint>", "build_name": "application-checkpoint-transfer-copy"}
import ../../../src/app/checkpoint_transfer
var original = default(PreparedApplicationCheckpoint)
var duplicate = original
discard original.error
discard duplicate.error
