# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A supplied anchor state cannot silently become a lookup-anchor state.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "got: ReportHash but wanted: ReportHash"}

import ../../../src/codec/work_report
let wrong = ReportHeader(lookupStateRoot: StateRoot())
discard wrong
