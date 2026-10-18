# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot forge success or change read-only result state.
import ../../../src/codec/state_outputs
var parsed = default(OutputLogResult[int])
parsed.error = OutputLogError.None
