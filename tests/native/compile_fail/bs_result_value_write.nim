# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Completed result storage is never mutable through the success accessor.
import ../../../src/bandersnatch/bandersnatch
var parsed = default(BsResult[BsKey])
parsed.value = default(BsKey)
