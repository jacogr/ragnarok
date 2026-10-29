# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Composite bank fields cannot bypass namespace or lifecycle ownership.
# @@Verification={"group": "privacy", "expected": "prefix"}
import ../../../src/state/checkpoint/bank as checkpoint_bank
let bank = default(CheckpointBank)
discard bank.prefix
