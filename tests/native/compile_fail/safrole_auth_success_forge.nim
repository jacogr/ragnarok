# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Statically known success is forbidden by the failure-only authentication result factory.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "contracts", "expected": "not reason == None"}

import ../../../src/state/safrole_authentication
discard safroleAuthFailure(SafroleAuthError.None)
