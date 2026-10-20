# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit synchronization receipts separate process-only ownership from a successful file barrier.
## Receipts describe the selected operation, not proof against hardware failure or chain authority.
type
  StorageDurability* {.pure.} = enum ## Default values make no persistence claim.
    Uninitialized, ProcessLifetime, FileAndDirectorySynced
