# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/app/current_download_policy as app_current_download_policy
let source = default(CurrentNamespacePolicyResult)
discard source.status
