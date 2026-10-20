# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Caller code cannot mutate or borrow raw native file ownership internals.
# @@Verification={"group": "privacy", "expected": "descriptor"}
import ../../../src/lib/atomic_file_writer
let writer = default(AtomicFileWriter)
discard writer.descriptor
