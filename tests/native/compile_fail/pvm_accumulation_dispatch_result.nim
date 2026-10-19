# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dispatch result snapshots remain private behind selected-success accessors.

import ../../../src/state/accumulation_dispatch
var outcome: AccumulationDispatchResult
discard outcome.completed
