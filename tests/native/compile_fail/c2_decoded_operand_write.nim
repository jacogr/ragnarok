# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot access or retag private C.2 result/variant state.
import ../../../src/codec/[c2_records, composite]
var value = default(AccumulationValue)
value.operand = default(OwnedOperand)
