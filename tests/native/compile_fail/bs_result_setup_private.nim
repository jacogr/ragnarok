# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Completed Bandersnatch storage remains private for this result instantiation.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/bandersnatch/bandersnatch
let parsed = default(BsResult[BsSetup])
discard parsed.completed
