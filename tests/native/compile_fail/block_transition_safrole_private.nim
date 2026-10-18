# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External safe code cannot read or retag private transition storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/state/block_transition
var outcome = default(BlockTransitionResult)
discard outcome.safroleReason # Must fail privacy checking before generating native code.
