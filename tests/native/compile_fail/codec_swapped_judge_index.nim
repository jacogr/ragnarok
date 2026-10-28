# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional rejection protects the public disputes type/ownership boundary.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: ValidatorIndex but wanted: JudgeIndex"}

import ../../../src/codec/disputes as codec_disputes
import ../../../src/codec/assurances as codec_assurances

var value: Judgment
value.judge = ValidatorIndex(1)
