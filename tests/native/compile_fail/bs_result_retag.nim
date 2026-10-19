# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default native results cannot be retagged as success.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/bandersnatch/bandersnatch
var parsed = default(BsResult[BsKey])
parsed.status = BsError.None
