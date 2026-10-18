# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot bypass guarded assurance results through count.
import ../../../src/codec/assurances
var value = default(AssuranceDecodeResult)
value.count = 0
