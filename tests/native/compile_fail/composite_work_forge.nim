# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Rejected misuse: guarded result/variant state cannot be accessed or retagged directly.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/[composite, work_digest]
discard WorkResult(status: CompositeError.None, decodedValue: successfulWork(BlobSpan()),
    byteConsumed: 2)
