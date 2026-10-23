# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Chunk mutation capabilities must remain private to the memory owner.
# @@Verification={"group": "privacy", "expected": "setPageByte"}
import ../../../src/pvm/machine
discard machine.setPageByte
