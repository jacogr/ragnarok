# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed observation/options owners cannot expose private successful state.
# @@Verification={"group": "privacy", "expected": "observations"}
import ../../../src/app/options
let source = default(Options)
discard source.observations
