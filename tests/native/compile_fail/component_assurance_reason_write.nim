# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot bypass private or read-only block result and cause state.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "assuranceError"}

import ../../../src/codec/block_codec
var value = default(FrameResult[int])
var cause = default(ComponentFailure)
cause.assuranceError = default(typeof(cause.assuranceError))
