# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exported leaf indices cannot substitute for an ordered import occurrence ordinal.

# @@Verification={"group": "nominal", "expected": "ImportInputIndex", "early": ["importInput(", "[3] expected: ImportInputIndex but got: ImportIndex"]}

import ../../../src/state/import_inputs
import ../../../src/codec/work_package
import ../../../src/pvm/host_fetch
discard importInput(default(VerifiedImportInputs), FetchItemIndex(0), ImportIndex(0))
