# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "keys"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/app/logical_service_proof
let source = default(LogicalServiceProof)
discard source.keys
