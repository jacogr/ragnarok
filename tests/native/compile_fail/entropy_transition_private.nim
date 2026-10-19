# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default results cannot expose posterior entropy/time through a public payload field.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "completed"}

import ../../../src/state/entropy
let hidden = default(EntropyTransitionResult[EntropyTimeUpdate])
discard hidden.completed
