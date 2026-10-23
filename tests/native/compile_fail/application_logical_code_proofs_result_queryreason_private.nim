# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "queryReason"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/app/logical_code_proof
let source = default(LogicalCodeProofResult[LogicalCodeProof])
discard source.queryReason
