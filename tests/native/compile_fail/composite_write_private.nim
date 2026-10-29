# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Rejected misuse: guarded result/variant state cannot be accessed or retagged directly.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "byteWritten"}

import ../../../src/codec/composite
import ../../../src/codec/work/digest as work_digest
let value = default(CompositeWrite)
discard value.byteWritten
