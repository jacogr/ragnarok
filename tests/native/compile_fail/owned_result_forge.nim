# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Rejected misuse: retained snapshot and result/variant state remain private.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/[owned, composite]
discard OwnedResult[int](status: OwnershipError.None, completed: 0)
