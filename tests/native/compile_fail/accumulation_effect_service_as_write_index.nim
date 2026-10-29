# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccumulationAccountWriteIndex", "early": ["effectAccountWriteKeyAt(", "[2] expected: AccumulationAccountWriteIndex but got: ServiceIndex"]}

## Reject a service identity used as an immutable traced-key ordinal.

import ../../../src/state/accumulation/effects as accumulation_effects
import ../../../src/codec/composite
discard effectAccountWriteKeyAt(default(AccumulationEffectContext), ServiceIndex(42))
