# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccumulationDeletedAccountIndex", "early": ["effectDeletedAccountAt(", "[2] expected: AccumulationDeletedAccountIndex but got: ServiceIndex"]}

## Reject a target service identity used as a captured deletion ordinal.

import ../../../src/state/accumulation_effects
import ../../../src/codec/composite
discard effectDeletedAccountAt(default(AccumulationEffectContext), ServiceIndex(77))
