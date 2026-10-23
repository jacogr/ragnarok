# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "logicalReason"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/state/supplied_proof_import
let source = default(SuppliedProofImportResult)
discard source.logicalReason
