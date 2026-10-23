# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Caller code cannot inspect or forge writer-owned page lookup metadata.
# @@Verification={"group": "privacy", "expected": "recent"}
import ../../../src/pvm/machine
let writer = newScalarMemoryWriter(captureMemory([], PageLimit(0)).value).value
discard writer.recent
