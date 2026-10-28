# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Completed/current versus configured source selection and retained logical provenance stay private.
# @@Verification={"group":"privacy","expected":"origin"}
import ../../../src/state/current_identities as state_current_identities
var owner: PreservedCurrentIdentities
discard owner.origin
