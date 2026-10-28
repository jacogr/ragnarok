# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot fabricate chapter results or expose/retag private parent/schedule
## storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/codec/state_consensus as codec_state_consensus
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_trie as codec_state_trie
let value = default(SafroleStateResult[StateBsKey])
discard value.completed
