# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Mutable writer backing remains private across every immutable publication boundary.
# @@Verification={"group": "privacy", "expected": "prepareWriterSpan"}
import ../../../src/pvm/machine
discard machine.prepareWriterSpan
