# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "accountKeys"}

## Reject raw access to the private self-key proof backing.

import ../../../src/state/accumulation_effects
discard default(AccumulationEffectContext).accountKeys
