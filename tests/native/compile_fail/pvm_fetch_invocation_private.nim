# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External code cannot bypass the invocation-fetch selected-success accessor.

## Verification: {"group": "privacy", "expected": "completed"}

import ../../../src/state/accumulation_fetch
var outcome: InvocationFetchResult
discard outcome.completed
