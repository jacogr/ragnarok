# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Operand payload hashes are not interchangeable with package identity hashes.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/[c2_records, work_report]
let value = AccumulationOperand(payloadHash: PackageHash())
discard value
