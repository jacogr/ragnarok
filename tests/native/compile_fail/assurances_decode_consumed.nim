# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot bypass guarded assurance results through byteConsumed.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "byteConsumed"}

import ../../../src/codec/assurances
var value = default(AssuranceDecodeResult)
echo value.byteConsumed
