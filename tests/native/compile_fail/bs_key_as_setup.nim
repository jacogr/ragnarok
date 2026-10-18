# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Scalar owners cannot select the ring setup allocator/domain.
import ../../../src/bandersnatch/bandersnatch
discard commitRing(default(BsKey), [])
