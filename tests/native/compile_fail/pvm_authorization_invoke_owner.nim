# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject authorization result forgery, source/CPU replacement and mixed independent local policy domains.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/authorization/invocation as authorization_invocation
var owner: AuthorizationInvocation
discard owner.data
