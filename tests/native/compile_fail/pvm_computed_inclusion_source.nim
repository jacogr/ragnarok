# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A caller-owned raw guarantee collection cannot replace verified computed batch authority.

# @@Verification={"group": "nominal", "expected": "ComputedGuaranteeBatch", "early": ["bindComputedInclusion(", "[1] expected: ComputedGuaranteeBatch but got: OwnedGuarantees"]}

import ../../../src/state/computed/inclusion as computed_inclusion
import ../../../src/codec/[guarantees, bounded]
discard bindComputedInclusion(default(OwnedGuarantees), ByteLimit(100000))
