# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "initialized"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/state/request_identity_history
let source = default(RequestIdentityHistory)
discard source.initialized
