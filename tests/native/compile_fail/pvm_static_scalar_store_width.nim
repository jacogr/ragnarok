# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Unsupported constant widths fail the scalar API precondition before any guest access.
# @@Verification={"group": "contracts", "expected": "0 == 1 or 0 == 2 or 0 == 4 or 0 == 8"}
import ../../../src/pvm/machine as pvm_machine
let pages = default(array[0, PageImage])
let writer = newScalarMemoryWriter(captureMemory(pages, PageLimit(1)).value).value
discard store[0](writer, MemoryAddress(65536), RegisterValue(1))
