# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedTerminalAccumulationProvisions", "early": ["integrateTerminalAccumulationProvisions(", "[2] expected: PreparedTerminalAccumulationProvisions but got: PreparedAccumulationProvisions"]}

## A caller-selected context union cannot substitute for a terminal-bound slot certificate.

import ../../../src/state/[accumulation_terminal_provisions, accumulation_provisions, store]
var state: StateStore
var plan: PreparedAccumulationProvisions
discard integrateTerminalAccumulationProvisions(state, plan)
