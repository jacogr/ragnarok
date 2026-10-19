# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Retained raw values remain private immutable storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "data"}

import ../../../src/codec/state_service_values
let owner = default(ServiceValueSnapshot)
discard owner.data
