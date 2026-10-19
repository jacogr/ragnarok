# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Mutation-scope provenance must remain private; callers cannot forge self-metadata eligibility.
# @@Verification={"group": "privacy", "expected": "accountScope"}

import ../../../src/state/accumulation_effects
discard default(AccumulationEffectContext).accountScope
