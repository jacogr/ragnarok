# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exclusive checkpoint lock ownership rejects actual composite duplication during ARC lowering.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <CheckpointWriter>", "build_name": "state-checkpoint-writer-copy"}
import ../../../src/state/checkpoint_writer
var original = default(CheckpointWriter)
var duplicate = original
discard original.close()
discard duplicate.close()
