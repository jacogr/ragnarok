# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Rejected misuse: guarded result/variant state cannot be accessed or retagged directly.
import ../../../src/codec/[composite, work_digest]
discard DigestResult(status: CompositeError.None, decodedValue: default(WorkDigest),
    byteConsumed: 0)
