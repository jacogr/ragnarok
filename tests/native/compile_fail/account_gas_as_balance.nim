# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Token balance cannot silently accept gas units.
import ../../../src/codec/state_accounts
let metadata = ServiceMetadata(balance: Gas(1))
discard metadata
