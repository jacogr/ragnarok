# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot access or retag private C.2 result/variant state.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "transferValue"}

import ../../../src/codec/[c2_records, composite]
var value = default(AccumulationSource)
discard value.transferValue
