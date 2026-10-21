# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "ancestorFiles"}

## Raw paths cannot activate an unvalidated or unrelated command.
import ../../../src/app/options
let selected = default(Options)
discard selected.ancestorFiles
