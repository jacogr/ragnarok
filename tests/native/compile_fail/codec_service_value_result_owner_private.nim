# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Successful service-value payloads are private behind the guarded accessor.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_trie as codec_state_trie
let parsed = default(ServiceValueResult[ServiceValueSnapshot])
discard parsed.completed
