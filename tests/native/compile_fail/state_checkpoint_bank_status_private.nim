# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bank results cannot expose private alternatives.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/state/checkpoint_bank
let outcome = default(CheckpointBankResult[int])
discard outcome.status
