# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe code cannot bypass the private report state through data.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/codec/composite as codec_composite
import ../../../src/codec/work_report as codec_work_report
import ../../../src/codec/report_owned as codec_report_owned
var value = default(OwnedReport)
discard value.data
