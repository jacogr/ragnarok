# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Successful account payloads are private behind the guarded result accessor.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_trie as codec_state_trie
let parsed = default(ServiceMetadataResult[StateEntry])
discard parsed.completed
