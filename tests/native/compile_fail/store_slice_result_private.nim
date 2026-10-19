# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Sliced byte results retain private payload storage behind the generic store success contract.

import ../../../src/state/store
var outcome: StateStoreResult[seq[byte]]
discard outcome.completed
