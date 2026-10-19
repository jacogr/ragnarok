# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dictionary ordinals cannot select configured core positions.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "PrivilegeEntryIndex"}

import ../../../src/codec/state_privileges
let owner = default(PrivilegeSnapshot)
discard privilegeAssignerAt(owner, PrivilegeEntryIndex(0))
