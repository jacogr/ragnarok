# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot retain or mutate a writer page vector outside its checked scalar API.
# @@Verification={"group": "privacy", "expected": "pages"}
import ../../../src/pvm/machine
let pages = default(array[0, PageImage])
let writer = newScalarMemoryWriter(captureMemory(pages, PageLimit(1)).value).value
discard writer.pages
