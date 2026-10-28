# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Gas cannot silently become a fixed E4 validator counter.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "ActivityGas"}

import ../../../src/codec/state_statistics as codec_state_statistics
var record: ValidatorActivity
record[ValidatorMeasure.Blocks] = ActivityGas(1)
