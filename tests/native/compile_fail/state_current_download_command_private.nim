# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current command progress cannot be retagged as successful adoption by external callers.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/app/current_download_command as app_current_download_command
var outcome = default(CurrentDownloadCommandOutcome)
discard outcome.status
