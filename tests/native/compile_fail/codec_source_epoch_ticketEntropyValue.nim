# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe code cannot bypass private/read-only header state through ticketEntropyValue.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "ticketEntropyValue"}

import ../../../src/codec/header as codec_header
var value = default(EpochMarker)
discard value.ticketEntropyValue
