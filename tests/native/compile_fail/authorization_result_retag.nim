# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, retag or fabricate authorization results or retained nested
## rows.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "status"}

import ../../../src/codec/[state_authorization, state_trie]
var value = default(AuthorizationResult[int])
value.status = AuthorizationError.None
