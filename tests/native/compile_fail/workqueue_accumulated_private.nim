# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Accumulated hash storage remains private and immutable after capture.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/state_workqueues
let owner = default(AccumulatedSnapshot)
discard owner.data
