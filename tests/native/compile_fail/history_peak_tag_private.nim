# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose private optional-peak storage.
import ../../../src/codec/state_history
let value = default(HistoryPeak)
discard value.isPresent
