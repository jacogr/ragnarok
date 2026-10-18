# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Captured owner storage cannot be replaced or exposed by an application.
import ../../../src/codec/state_outputs
var owner = default(OutputLogSnapshot)
owner.data = nil
