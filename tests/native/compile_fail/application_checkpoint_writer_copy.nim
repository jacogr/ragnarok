# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Composite native ownership rejects implicit duplication during actual ARC lowering.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <ApplicationCheckpointWriter>", "build_name": "application-checkpoint-writer-copy"}
import ../../../src/app/checkpoint_writer
var original = default(ApplicationCheckpointWriter)
var duplicate = original
discard original.close()
discard duplicate.close()
