# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "downloadCount"}

## Finite requests and confirmed progress cannot be manufactured through private fields.
import ../../../src/app/options as app_options
let owner = default(Options)
discard owner.downloadCount
