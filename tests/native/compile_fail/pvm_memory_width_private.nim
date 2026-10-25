# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A copied memory-fact value exposes queries, never mutable backing fields.
# @@Verification={"group": "privacy", "expected": "widthValue"}
import ../../../src/pvm/program
let copied = default(MemoryOperands)
discard copied.widthValue
