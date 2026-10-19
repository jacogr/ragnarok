# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot fabricate chapter results or expose/retag private parent/schedule
## storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "status"}

import ../../../src/codec/[state_consensus, state_safrole, state_trie]
discard SafroleStateResult[SafroleStateInfo](status: StateComponentError.None)
