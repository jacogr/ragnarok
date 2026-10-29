# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Finite requests and confirmed progress cannot be manufactured through private fields.
import ../../../src/app/download/command as download_command
let owner = default(DownloadCommandOutcome)
discard owner.status
