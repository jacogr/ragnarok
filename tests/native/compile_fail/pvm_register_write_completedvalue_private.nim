# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed scalar arithmetic results cannot expose or forge their private payload/status.
# @@Verification={"group": "privacy", "expected": "completedValue"}
import ../../../src/pvm/registers as pvm_registers
let written = default(RegisterWriteResult)
discard written.completedValue
