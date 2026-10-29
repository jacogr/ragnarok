# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject access to private batch authority or result selection.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed/batch as computed_batch
discard default(ComputedGuaranteeBatch).data
