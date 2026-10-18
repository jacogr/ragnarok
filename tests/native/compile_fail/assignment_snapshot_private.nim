# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot inject or mutate retained assignment/report backing storage.
import ../../../src/codec/state_availability
let owner = AvailabilitySnapshot(data: nil)
discard owner
