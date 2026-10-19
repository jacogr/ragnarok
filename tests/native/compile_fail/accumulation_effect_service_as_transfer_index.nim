# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccumulationTransferIndex", "early": ["effectTransferAt(", "[2] expected: AccumulationTransferIndex but got: ServiceIndex"]}

## Reject an account identity used as an outgoing transfer ordinal.

import ../../../src/state/accumulation_effects
import ../../../src/codec/composite
discard effectTransferAt(default(AccumulationEffectContext), ServiceIndex(42))
