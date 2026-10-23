# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "source"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/app/paged_logical_proof
let source = default(LogicalProofPage)
discard source.source
