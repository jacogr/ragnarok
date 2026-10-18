# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The failure reason has no mutable public field.
import ../../../src/bandersnatch/bandersnatch
var parsed = default(BsResult[BsKey])
parsed.error = BsError.None
