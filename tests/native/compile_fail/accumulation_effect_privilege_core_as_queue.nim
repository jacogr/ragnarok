# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AuthorizationCoreIndex", "early": ["recordAccumulationAssign(", "[2] expected: AuthorizationCoreIndex but got: PrivilegeCoreIndex"]}

## Reject a privilege ordinal used as an authorization queue selector at the mutation boundary.

import ../../../src/state/accumulation/effects as accumulation_effects
import ../../../src/codec/state/[authorization as state_authorization,
    privileges as state_privileges]
import ../../../src/codec/composite
discard recordAccumulationAssign(default(AccumulationEffects), PrivilegeCoreIndex(0), [],
  ServiceIndex(0), default(AuthorizationConfig), default(PrivilegeConfig))
