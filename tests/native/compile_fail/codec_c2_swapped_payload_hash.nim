# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Operand payload hashes are not interchangeable with package identity hashes.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal","expected": "got: ReportHash[0] but wanted: PayloadHash"}

import ../../../src/codec/c2_records as codec_c2_records
import ../../../src/codec/work_report as codec_work_report
let value = AccumulationOperand(payloadHash: PackageHash())
discard value
