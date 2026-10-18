# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## An entropy word cannot silently become the current state timeslot.
import ../../../src/codec/state_safrole
let word = default(StateEntropyWord)
let entry = timeEntry(word)
discard entry
