# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## State callers cannot bypass typed state/root adapters through the underlying raw file owner.
# @@Verification={"group": "privacy", "expected": "native"}
import ../../../src/state/checkpoint/writer as checkpoint_writer
let writer = default(CheckpointWriter)
discard writer.native
