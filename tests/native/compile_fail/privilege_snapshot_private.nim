# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Retained arrays remain private; callers cannot mutate them through owner handles.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/state_privileges
let owner = default(PrivilegeSnapshot)
discard owner.data
