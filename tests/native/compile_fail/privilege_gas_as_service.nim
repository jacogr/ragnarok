# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Gas is not a role service, even when its numeric value would fit E4.
import ../../../src/codec/state_privileges
let state = PrivilegeState(manager: PrivilegeGas(1))
discard state
