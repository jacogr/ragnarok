# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject authorization result forgery, source/CPU replacement and mixed independent local policy domains.

# @@Verification={"group": "nominal", "expected": "StateStoreSnapshot", "early": ["runAuthorizationInvocation(", "[1] expected: StateStoreSnapshot but got: Machine"]}

import ../../../src/state/authorization_invocation
import ../../../src/pvm/machine
import ../../../src/codec/[work_package, work_report]
import ../../../src/chain/parameters
discard runAuthorizationInvocation(default(Machine), default(OwnedWorkPackage), CoreIndex(0),
    default(Parameters), default(AuthorizationInvocationLimits))
