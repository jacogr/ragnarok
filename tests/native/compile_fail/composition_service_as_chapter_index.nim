# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Service identities cannot address the fixed nominal chapter container.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/[state_composition, state_accounts]
let chapters = default(StateChapters)
discard chapters[ServiceIndex(1)]
