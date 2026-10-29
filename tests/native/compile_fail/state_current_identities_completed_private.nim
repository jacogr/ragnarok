# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Identity preservation ownership and result authority remain private.
# @@Verification={"group":"privacy","expected":"completed"}
import ../../../src/state/current/identities as current_identities
var owner: CurrentIdentityResult[PreservedCurrentIdentities]
discard owner.completed
