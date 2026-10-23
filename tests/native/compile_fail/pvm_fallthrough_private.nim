# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Only the owner decoder may populate the executable fallthrough capability.
# @@Verification={"group": "privacy", "expected": "fallthroughPresent"}
import ../../../src/pvm/program
let decoded = instruction(default(Program), CodeAddress(0))
discard decoded.value.fallthroughPresent
