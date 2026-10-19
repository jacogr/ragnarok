# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: Checks that extracting a known failed ParameterResult is rejected at compile time.
## Verification: {"group": "contracts", "expected": "decoded.success"}

import std/assertions
import ../../../src/chain/parameters
let decoded = decodeParameters([])
assert not decoded.ok
discard decoded.value
