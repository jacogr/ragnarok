# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External safe code cannot read or retag private transition storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/state/disputes
var outcome = default(DisputesPlan)
discard outcome.data # Must fail privacy checking before generating native code.
