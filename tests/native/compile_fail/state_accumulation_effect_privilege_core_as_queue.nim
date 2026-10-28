# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AuthorizationCoreIndex", "early": ["recordAccumulationAssign(", "[2] expected: AuthorizationCoreIndex but got: PrivilegeCoreIndex"]}

## Reject a privilege ordinal used as an authorization queue selector at the mutation boundary.

import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/codec/state_authorization as codec_state_authorization
import ../../../src/codec/state_privileges as codec_state_privileges
import ../../../src/codec/composite as codec_composite
discard recordAccumulationAssign(default(AccumulationEffects), PrivilegeCoreIndex(0), [],
  ServiceIndex(0), default(AuthorizationConfig), default(PrivilegeConfig))
