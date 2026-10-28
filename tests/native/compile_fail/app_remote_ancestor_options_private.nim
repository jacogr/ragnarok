# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "remoteAncestors"}

## Unvalidated configuration cannot enable outgoing ancestry acquisition through raw field writes.
import ../../../src/app/options as app_options
var selected = default(Options)
selected.remoteAncestors = 1
