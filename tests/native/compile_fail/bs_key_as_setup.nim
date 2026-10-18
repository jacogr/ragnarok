# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Scalar owners cannot select the ring setup allocator/domain.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/bandersnatch/bandersnatch
discard commitRing(default(BsKey), [])
