# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, forge or mutate private chapter-10 results, owners or
## alternatives.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/codec/state/[availability as state_availability, trie as state_trie]
discard AvailabilityResult[AvailabilityInfo](status: AvailabilityError.None)
