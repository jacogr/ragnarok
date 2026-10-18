# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe code cannot bypass private guarantee state through data.
import ../../../src/codec/guarantees
var value = default(OwnedGuarantees)
discard OwnedGuarantees(data: nil)
