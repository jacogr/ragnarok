# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject authorization result forgery, source/CPU replacement and mixed independent local policy domains.

# @@Verification={"group": "nominal", "expected": "StateStoreSnapshot", "early": ["runAuthorizationInvocation(", "[1] expected: StateStoreSnapshot but got: Machine"]}

import ../../../src/state/authorization_invocation as state_authorization_invocation
import ../../../src/pvm/machine as pvm_machine
import ../../../src/codec/work_package as codec_work_package
import ../../../src/codec/work_report as codec_work_report
import ../../../src/chain/parameters as chain_parameters
discard runAuthorizationInvocation(default(Machine), default(OwnedWorkPackage), CoreIndex(0),
    default(Parameters), default(AuthorizationInvocationLimits))
