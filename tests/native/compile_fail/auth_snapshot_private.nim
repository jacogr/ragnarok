# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Caller code cannot replace or expose the private mutable object underlying an immutable
## snapshot.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/state_authorization
let owner = AuthorizationSnapshot(data: nil)
discard owner
