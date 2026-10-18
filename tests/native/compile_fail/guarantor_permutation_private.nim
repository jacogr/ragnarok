# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot access private guarantor storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/state/guarantors
let owner = default(GuarantorPermutation)
discard owner.data # Must fail during semantic compilation.
