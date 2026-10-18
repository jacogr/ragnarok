# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Lookup-anchor timeslots cannot silently become guarantee evaluation timeslots.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/[guarantees, work_report]
let wrong = Guarantee(slot: LookupSlot(1))
discard wrong
