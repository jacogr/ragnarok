# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot convert a default failure into success by changing a result discriminator.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "status"}

import ../../../src/state/authorization
import ../../../src/codec/state_trie
var hidden = default(AuthorizationTransitionResult[StateEntry])
hidden.status = AuthorizationTransitionError.None
