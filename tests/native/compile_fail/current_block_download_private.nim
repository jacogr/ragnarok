# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Mutable current reception and its worker-borrow state remain private to the original owner.
# @@Verification={"group": "privacy", "expected": "pending"}
import ../../../src/app/current_block_download
var receiver = default(CurrentBlockDownload)
discard receiver.pending
