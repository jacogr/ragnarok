# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject bypassing validated executable state activation and typed budget ownership.
# @@Verification={"group": "privacy", "expected": "state"}

import ../../../src/app/options
var configuration = default(Options)
discard configuration.state
