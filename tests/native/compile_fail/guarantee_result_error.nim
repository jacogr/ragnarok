# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe code cannot bypass private guarantee state through error.
import ../../../src/codec/guarantees
var value = default(GuaranteeResult[int])
value.error = GuaranteeError.None
