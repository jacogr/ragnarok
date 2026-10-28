# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The native child, destination path and lock descriptor cannot escape the composite boundary.
# @@Verification={"group": "privacy", "expected": "native"}
import ../../../src/app/checkpoint_writer as app_checkpoint_writer
let writer = default(ApplicationCheckpointWriter)
discard writer.native
