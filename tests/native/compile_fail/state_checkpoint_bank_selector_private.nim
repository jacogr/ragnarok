# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Composite bank fields cannot bypass namespace or lifecycle ownership.
# @@Verification={"group": "privacy", "expected": "selector"}
import ../../../src/state/checkpoint_bank as state_checkpoint_bank
let bank = default(CheckpointBank)
discard bank.selector
