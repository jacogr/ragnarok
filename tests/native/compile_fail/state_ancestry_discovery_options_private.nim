# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "discoverAncestors"}

## Validated on-demand activation cannot be forged by direct field mutation or extraction.
import ../../../src/app/options
let options = default(Options)
discard options.discoverAncestors
