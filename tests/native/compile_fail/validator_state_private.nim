# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Result storage stays private; failed/default snapshots cannot be exposed or retagged.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "completed"}

import ../../../src/state/validator_state
var hidden = default(ValidatorStateResult)
discard hidden.completed
