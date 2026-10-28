# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot expose, forge or mutate private chapter-10 results, owners or
## alternatives.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "isPresent"}

import ../../../src/codec/state_availability as codec_state_availability
import ../../../src/codec/state_trie as codec_state_trie
var value = default(AvailabilityAssignment)
value.isPresent = true
