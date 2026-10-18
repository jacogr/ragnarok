# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Completed result storage is never mutable through the success accessor.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/bandersnatch/bandersnatch
var parsed = default(BsResult[BsKey])
parsed.value = default(BsKey)
