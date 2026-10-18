# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Retained raw values remain private immutable storage.
import ../../../src/codec/state_service_values
let owner = default(ServiceValueSnapshot)
discard owner.data
