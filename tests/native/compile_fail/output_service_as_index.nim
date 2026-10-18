# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Service IDs cannot substitute for output-sequence ordinals.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/state_outputs
let owner = default(OutputLogSnapshot)
discard outputLogAt(owner, ServiceIndex(0))
