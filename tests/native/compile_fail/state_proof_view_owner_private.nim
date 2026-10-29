# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot fabricate partial verified state or nested success/failure payloads.
# @@Verification={"group": "privacy", "expected": "data"}
import ../../../src/state/proof/view as proof_view
let owner = default(ProofView)
discard owner.data
