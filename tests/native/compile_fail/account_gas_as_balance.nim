# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Token balance cannot silently accept gas units.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "got: Gas but wanted: AccountBalance"}

import ../../../src/codec/state_accounts
let metadata = ServiceMetadata(balance: Gas(1))
discard metadata
