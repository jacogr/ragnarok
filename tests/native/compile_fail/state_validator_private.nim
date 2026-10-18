# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot inject or mutate private retained validator backing storage.
import ../../../src/codec/state_safrole
let snapshot = ValidatorStateSnapshot(data: nil)
discard snapshot
