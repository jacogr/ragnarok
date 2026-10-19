# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External-input capture storage cannot be extracted or mutated through the public context handle.

## Verification: {"group": "privacy", "expected": "inputData"}

import ../../../src/pvm/host_fetch
let context = default(FetchContext)
discard context.inputData
