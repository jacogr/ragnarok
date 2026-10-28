# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "info"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/state/supplied_services as state_supplied_services
let source = default(SuppliedServicesPlan)
discard source.info
