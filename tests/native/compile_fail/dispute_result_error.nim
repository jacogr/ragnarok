# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe code cannot bypass private dispute state through error.
import ../../../src/codec/disputes
var value = default(DisputeResult[int])
value.error = DisputeError.None
