# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A caller-owned raw guarantee collection cannot replace verified computed batch authority.

# @@Verification={"group": "nominal", "expected": "ComputedGuaranteeBatch", "early": ["bindComputedInclusion(", "[1] expected: ComputedGuaranteeBatch but got: OwnedGuarantees"]}

import ../../../src/state/computed_inclusion as state_computed_inclusion
import ../../../src/codec/guarantees as codec_guarantees
import ../../../src/codec/bounded as codec_bounded
discard bindComputedInclusion(default(OwnedGuarantees), ByteLimit(100000))
