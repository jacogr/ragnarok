# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional nominal domain misuse must fail compilation.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: CoreCount but wanted: ValidatorIndex"}

import ../../../src/codec/assurances
let value: ValidatorIndex = CoreCount(0)
discard value
