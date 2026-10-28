# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/state/supplied_proof_import as state_supplied_proof_import
let source = default(SuppliedProofImportResult)
discard source.status
