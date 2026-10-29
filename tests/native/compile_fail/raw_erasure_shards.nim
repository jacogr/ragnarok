# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A host integer cannot implicitly identify an assuring validator-set cardinality.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: uint16 but wanted: ErasureShards"}

import ../../../src/codec/work/report as work_report
let wrong = ReportHeader(erasureShards: 6'u16)
discard wrong
