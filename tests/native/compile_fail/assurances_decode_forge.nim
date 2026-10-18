# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot bypass guarded assurance results through status.
import ../../../src/codec/assurances
var value = default(AssuranceDecodeResult)
discard AssuranceDecodeResult(status: AssuranceError.None)
