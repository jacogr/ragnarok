# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationBatch", "early": ["applyAccumulationBatch(", "[2] expected: PreparedAccumulationBatch but got: PreparedTerminalAccumulationProvisions"]}

## A terminal-selected union is not a common-source account-publication certificate.

import ../../../src/state/[accumulation_batch, accumulation_terminal_provisions, store]
var state: StateStore
var plan: PreparedTerminalAccumulationProvisions
discard applyAccumulationBatch(state, plan)
