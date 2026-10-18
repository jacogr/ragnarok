# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default results cannot expose posterior entropy/time through a public payload field.
import ../../../src/state/entropy
let hidden = default(EntropyTransitionResult[EntropyTimeUpdate])
discard hidden.completed
