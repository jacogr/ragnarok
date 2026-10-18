# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## An anchor time cannot silently become a lookup-anchor time.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/work_report
let wrong = ReportHeader(anchorSlot: LookupSlot(0))
discard wrong
