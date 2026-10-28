# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "got: ServiceIndex but wanted: AccumulationDesiredService"}

## Reject a narrow existing service identity used as the full-width creation proposal domain.

import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/codec/composite as codec_composite
let proposal = AccumulationNewService(desired: ServiceIndex(7))
discard proposal
