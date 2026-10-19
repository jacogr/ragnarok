# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Captured chapter/mapping storage cannot be rebound by application callers.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "data"}

import ../../../src/codec/state_composition
var owner = default(StateSnapshot)
owner.data = nil
