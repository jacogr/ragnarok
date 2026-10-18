# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The public reason is read-only and raw result status stays private.
import ../../../src/bandersnatch/bandersnatch
let parsed = default(BsResult[BsKey])
discard parsed.status
