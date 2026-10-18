# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Chapter slots remain private behind nominal chapter accessors.
import ../../../src/codec/state_composition
let chapters = default(StateChapters)
discard chapters.slots
