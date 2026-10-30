# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Integration callers cannot forge success or mutate private snapshot/bank storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "value"}

import "../../../src/jamnp-s/integration"
import ../../../src/codec/owned
var checked = default(IntegrationResult[int])
checked.value = 0
