# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot extract a cached private page or bypass scalar checks after publication.
# @@Verification={"group": "privacy", "expected": "writePage"}
import ../../../src/pvm/machine
let writer = newScalarMemoryWriter(emptyMemory(PageLimit(1)).value).value
discard writer.writePage
