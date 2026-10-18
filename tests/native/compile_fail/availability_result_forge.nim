# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, forge or mutate private chapter-10 results, owners or alternatives.
import ../../../src/codec/[state_availability, state_trie]
discard AvailabilityResult[AvailabilityInfo](status: AvailabilityError.None)
