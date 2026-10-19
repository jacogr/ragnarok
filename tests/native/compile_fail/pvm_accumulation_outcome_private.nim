# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Outcome storage and result alternatives remain private behind guarded accessors.

import ../../../src/state/accumulation_outcome
var owner: AccumulationOutcome
discard owner.data
