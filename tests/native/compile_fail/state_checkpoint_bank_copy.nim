# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Composite bank ownership independently rejects ARC duplication.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <CheckpointBank>", "build_name": "state-checkpoint-bank-copy"}
import ../../../src/state/checkpoint_bank as state_checkpoint_bank
var original = default(CheckpointBank)
var duplicate = original
discard original.close()
discard duplicate.close()
