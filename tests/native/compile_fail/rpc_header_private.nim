# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: Reject external access to the retained genesis header owner.
import ../../../src/chain/genesis
var view = default(Genesis)
discard view.sealedHeader
