# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A core ordinal cannot be passed as a header authorization timeslot.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "AuthorizationCoreIndex", "early": ["advanceAuthorization(", "[4] expected: AuthorizationSlot but got: AuthorizationCoreIndex"]}

import ../../../src/state/authorization
import ../../../src/codec/state_authorization
let owner = default(AuthorizationSnapshot)
discard advanceAuthorization(owner, owner, [], AuthorizationCoreIndex(0), default(AuthorizationConfig))
