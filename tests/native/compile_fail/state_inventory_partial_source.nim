# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "ValidatedStateManifest", "early": ["captureStateInventory(", "[1] expected: ValidatedStateManifest but got: ProofView"]}

## Nominal coordinates and partial evidence cannot impersonate compact source authority.
import ../../../src/state/inventory
import ../../../src/state/proof_view
discard captureStateInventory(default(ProofView), [], StateInventoryLimits())
