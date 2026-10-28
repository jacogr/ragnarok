# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "data"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/state/code_availability as state_code_availability
let source = default(StateCodeAvailability)
discard source.data
