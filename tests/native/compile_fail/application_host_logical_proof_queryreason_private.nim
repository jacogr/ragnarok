# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "queryReason"}

## Host logical authority and backing storage remain private and cannot be retagged or substituted.
import ../../../src/app/logical/proof as logical_proof
let source = default(LogicalProofResult)
discard source.queryReason
