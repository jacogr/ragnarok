# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler rejection fixture protecting private invocation storage and nominal indexing.
## Its top-level access/call must fail compilation rather than expose or forge validated values.

import ../../../src/state/[accumulation_inputs, accumulation_operands]
import ../../../src/codec/composite
let owner = default(InvocationInput)
discard owner.transferValue
