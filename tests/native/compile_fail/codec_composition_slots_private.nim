# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Chapter slots remain private behind nominal chapter accessors.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "slots"}

import ../../../src/codec/state_composition as codec_state_composition
let chapters = default(StateChapters)
discard chapters.slots
