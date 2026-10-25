# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Unsupported constant widths fail the scalar API precondition before any guest access.
# @@Verification={"group": "contracts", "expected": "3 == 1 or 3 == 2 or 3 == 4 or 3 == 8"}
import ../../../src/pvm/machine
let pages = default(array[0, PageImage])
let writer = newScalarMemoryWriter(captureMemory(pages, PageLimit(1)).value).value
discard load[3](writer, MemoryAddress(65536))
