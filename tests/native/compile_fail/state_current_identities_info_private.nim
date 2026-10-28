# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Identity preservation ownership and result authority remain private.
# @@Verification={"group":"privacy","expected":"info"}
import ../../../src/state/current_identities as state_current_identities
var owner: PreservedCurrentIdentities
discard owner.info
