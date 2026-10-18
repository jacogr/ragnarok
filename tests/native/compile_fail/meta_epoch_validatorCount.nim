# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe code cannot bypass private/read-only header state through validatorCount.
import ../../../src/codec/header
var value = default(EpochMarkerInfo)
discard value.validatorCount
