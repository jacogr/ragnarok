# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "metadataReason"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/state/storage_logical_continuation
let source = default(StorageContinuationResult)
discard source.metadataReason
