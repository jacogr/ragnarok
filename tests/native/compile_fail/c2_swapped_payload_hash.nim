# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Operand payload hashes are not interchangeable with package identity hashes.
import ../../../src/codec/[c2_records, work_report]
let value = AccumulationOperand(payloadHash: PackageHash())
discard value
