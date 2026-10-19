# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Balance and gas share a width but remain independent protocol units.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "got: TransferBalance but wanted: Gas"}

import ../../../src/codec/c2_records
let value = DeferredTransfer(gas: TransferBalance(1))
discard value
