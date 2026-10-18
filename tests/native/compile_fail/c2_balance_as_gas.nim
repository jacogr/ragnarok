# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Balance and gas share a width but remain independent protocol units.
import ../../../src/codec/c2_records
let value = DeferredTransfer(gas: TransferBalance(1))
discard value
