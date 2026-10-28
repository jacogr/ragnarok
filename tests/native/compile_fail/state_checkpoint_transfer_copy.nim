# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepared buffers cannot acquire a second implicit owner during actual ARC lowering.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <PreparedCheckpoint>", "build_name": "state-checkpoint-transfer-copy"}
import ../../../src/state/checkpoint_transfer as state_checkpoint_transfer
var original = default(PreparedCheckpoint)
var duplicate = original
discard original.error
discard duplicate.error
