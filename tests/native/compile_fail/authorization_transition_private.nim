# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default transition result payloads are never public fields.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/state/authorization
import ../../../src/codec/state_trie
let hidden = default(AuthorizationTransitionResult[StateEntry])
discard hidden.completed
