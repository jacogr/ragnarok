# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject a raw uint64 assigned to the nominal accumulateGas field of WorkDigest.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: uint64 but wanted: Gas"}

import ../../../src/codec/work_digest
var wrong = default(uint64)
var value = default(WorkDigest)
value.accumulateGas = wrong
