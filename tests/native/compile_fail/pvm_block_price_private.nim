# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Cached prices and their program/limit lifetime belong only to the private invocation.
# @@Verification={"group": "privacy", "expected": "cachedCharge"}
import ../../../src/pvm/step as pvm_step
discard pvm_step.cachedCharge
