# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Public storage APIs must not expose mutable owners or unchecked result payloads.
import ../../../src/state/store

let hidden = default(StateStoreResult[StateStoreSnapshot])
discard hidden.completed
