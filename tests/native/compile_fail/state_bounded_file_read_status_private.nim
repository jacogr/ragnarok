# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw file read alternatives cannot be retagged or extracted through unguarded byte storage.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/lib/atomic_file
let outcome = default(BoundedFileResult)
discard outcome.status
