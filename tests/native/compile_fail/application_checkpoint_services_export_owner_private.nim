# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Service callers cannot bypass the managed receipt journal or access the fixed-address child.
# @@Verification={"group": "privacy", "expected": "checkpointExport"}
import ../../../src/app/services
let owner = default(Services)
discard owner.checkpointExport
