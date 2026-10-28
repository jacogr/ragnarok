# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "completed"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/app/frozen_supplied as app_frozen_supplied
let source = default(FrozenSuppliedResult[int])
discard source.completed
