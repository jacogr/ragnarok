# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Captured owner storage cannot be replaced or exposed by an application.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "data"}

import ../../../src/codec/state_outputs
var owner = default(OutputLogSnapshot)
owner.data = nil
