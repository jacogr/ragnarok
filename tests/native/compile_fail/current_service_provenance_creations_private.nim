# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "creations"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/state/service_identity_history
let source = default(ServiceIdentityHistory)
discard source.creations
