# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/state/proof_state_import as state_proof_state_import
let source = default(ProofStateImportResult)
discard source.status
