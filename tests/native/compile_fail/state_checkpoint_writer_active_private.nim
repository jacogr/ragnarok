# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Caller code cannot mutate native checkpoint ownership or borrow its private path/descriptor.
# @@Verification={"group": "privacy", "expected": "active"}
import ../../../src/state/checkpoint_writer
let writer = default(CheckpointWriter)
discard writer.active
