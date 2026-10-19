# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compilation fixture protecting preimage admission provenance and selected-result storage.
## Direct field access must fail before callers can forge owners, retag refusals or read partial success.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/preimages
let owner = default(PreimageTransitionResult[AdmittedPreimages])
discard owner.completed # Storage remains private.
