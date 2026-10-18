# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional rejection keeps immutable header/marker snapshot storage private.
import ../../../src/codec/header

var owner: OwnedUnsignedHeader
discard owner.data
