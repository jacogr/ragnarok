# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: Reject external access to the cached genesis erasure piece length.
import ../../../src/chain/genesis
var view = default(Genesis)
discard view.pieceLength
