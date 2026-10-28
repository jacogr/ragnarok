# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccumulationCreatedAccountIndex", "early": ["effectCreatedAccountAt(", "[2] expected: AccumulationCreatedAccountIndex but got: ServiceIndex"]}

## Reject a service identity used as a captured-creation ordinal.

import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/codec/composite as codec_composite
discard effectCreatedAccountAt(default(AccumulationEffectContext), ServiceIndex(42))
