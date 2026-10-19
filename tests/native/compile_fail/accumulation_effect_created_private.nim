# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "created"}

## Reject raw access to the private captured created-account owner.

import ../../../src/state/accumulation_effects
discard default(AccumulationEffectContext).created
