# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject a payload hash assigned to the distinct code-hash field of WorkDigest.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "got: PayloadHash but wanted: CodeHash"}

import ../../../src/codec/work_digest
var wrong = default(PayloadHash)
var value = default(WorkDigest)
value.codeHash = wrong
