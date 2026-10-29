# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "data"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/state/accumulation/effects as accumulation_effects
let source = default(AccumulationStorageFact)
discard source.data
