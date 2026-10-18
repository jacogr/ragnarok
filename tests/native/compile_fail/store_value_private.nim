# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Public storage APIs must not expose mutable owners or unchecked result payloads.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/state/store

let hidden = default(StateValue)
discard hidden.owner
