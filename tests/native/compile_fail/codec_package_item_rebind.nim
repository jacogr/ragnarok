# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot bypass private package/import state through index.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "index"}

import ../../../src/codec/work_package as codec_work_package
import ../../../src/codec/work_report as codec_work_report
var value = default(OwnedWorkItem)
value.index = 0
