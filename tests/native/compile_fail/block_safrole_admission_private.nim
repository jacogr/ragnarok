# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Binding and commitment payloads/discriminators remain private across all alternatives.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/state/block_admission
import ../../../src/codec/header
var hidden = default(BlockSafroleResult)
discard hidden.admissionReason
