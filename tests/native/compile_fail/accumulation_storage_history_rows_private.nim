# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "rows"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/state/accumulation/storage_history as accumulation_storage_history
let source = default(StorageHistory)
discard source.rows
