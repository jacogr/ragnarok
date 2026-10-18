# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import ../../../src/codec/work_report
# An anchor time cannot silently become a lookup-anchor time.
let wrong = ReportHeader(anchorSlot: LookupSlot(0))
discard wrong
