# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dictionary ordinals cannot select configured core positions.
import ../../../src/codec/state_privileges
let owner = default(PrivilegeSnapshot)
discard privilegeAssignerAt(owner, PrivilegeEntryIndex(0))
