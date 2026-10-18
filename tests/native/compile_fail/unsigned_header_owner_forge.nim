# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe code cannot bypass private/read-only header state through data.
import ../../../src/codec/header
var value = default(OwnedUnsignedHeader)
discard OwnedUnsignedHeader(data: nil)
