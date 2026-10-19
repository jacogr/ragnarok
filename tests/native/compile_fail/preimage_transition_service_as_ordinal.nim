# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compilation fixture separating protocol service/slot domains from transition API positions.
## The mismatched call must fail semantic compilation before publication or extraction.

# @@Verification={"group": "nominal", "expected": "ProvisionIndex", "early": ["provisionAt(", "[2] expected: ProvisionIndex but got: ServiceIndex"]}

import ../../../src/state/[preimages, store]
import ../../../src/codec/[composite, state_requests]
discard provisionAt(default(AdmittedPreimages), ServiceIndex(0))
