# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Result status is read-only; callers cannot retag a failure/default into successful payload
## access.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "status"}

import ../../../src/state/store

var hidden = default(StateStoreResult[StateStore])
hidden.status = StateStoreError.None
