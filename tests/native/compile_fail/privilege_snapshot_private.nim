# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Retained arrays remain private; callers cannot mutate them through owner handles.
import ../../../src/codec/state_privileges
let owner = default(PrivilegeSnapshot)
discard owner.data
