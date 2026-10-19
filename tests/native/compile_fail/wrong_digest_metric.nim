# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject an import count assigned to a different work-digest resource metric.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: ImportCount but wanted: ExportCount"}

import ../../../src/codec/work_digest
var wrong = default(ImportCount)
var value = default(RefineLoad)
value.exports = wrong
