# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional rejection protects a nominal header field or sealed/unsigned ownership boundary.
import ../../../src/codec/[header]

var value: WinningTicket
value.id = EpochEntropy(default(array[32, byte]))
