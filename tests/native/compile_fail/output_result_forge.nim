# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot forge success or change read-only result state.
import ../../../src/codec/state_outputs
discard OutputLogResult[int](status: OutputLogError.None, completed: 0)
