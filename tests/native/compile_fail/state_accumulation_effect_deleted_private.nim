# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "deleted"}

## Reject raw access to the private captured deletion proof owner.

import ../../../src/state/accumulation_effects as state_accumulation_effects
discard default(AccumulationEffectContext).deleted
