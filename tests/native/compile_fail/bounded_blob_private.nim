# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Rejected misuse: bounded result state is private and its public reason is read-only.
import ../../../src/codec/bounded
let value = default(BlobResult)
discard value.byteLength
