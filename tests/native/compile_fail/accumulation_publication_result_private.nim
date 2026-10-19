# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Refuse raw construction or retagging of original-block-bound accumulation publication.

import ../../../src/state/accumulation_publication
var outcome: AccumulationPublicationResult[PreparedAccumulationPublication]
discard outcome.completed
