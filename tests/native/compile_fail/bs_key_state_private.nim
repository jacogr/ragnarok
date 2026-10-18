# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Scalar owners do not expose native pointers or mutable ARC storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/bandersnatch/bandersnatch
let key = default(BsKey)
discard key.state
