# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional nominal domain misuse must fail compilation.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: ValidatorCount but wanted: CoreCount"}

import ../../../src/codec/assurances as codec_assurances
let value = AssuranceConfig(cores: ValidatorCount(2), validators: CoreCount(6))
discard value
