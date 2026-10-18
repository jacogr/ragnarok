# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External code cannot mutate immutable operand backing bytes or private spans.
import ../../../src/codec/c2_records
var owner: OwnedOperand
discard owner.data
