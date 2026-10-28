# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedTerminalAccumulationProvisions", "early": ["integrateTerminalAccumulationProvisions(", "[2] expected: PreparedTerminalAccumulationProvisions but got: PreparedAccumulationProvisions"]}

## A caller-selected context union cannot substitute for a terminal-bound slot certificate.

import ../../../src/state/accumulation_terminal_provisions as state_accumulation_terminal_provisions
import ../../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../../src/state/store as state_store
var state: StateStore
var plan: PreparedAccumulationProvisions
discard integrateTerminalAccumulationProvisions(state, plan)
