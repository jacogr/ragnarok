# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bank results cannot expose private alternatives.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/state/checkpoint/bank as checkpoint_bank
let outcome = default(CheckpointBankResult[int])
discard outcome.completed
