# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Initial membership and actual header evidence cannot be overwritten through a public owner.
# @@Verification={"group": "privacy", "expected": "data"}
import ../../../src/state/fuzz_ancestry
let context = default(FuzzAncestry)
discard context.data
