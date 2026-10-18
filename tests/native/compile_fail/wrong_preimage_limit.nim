# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deliberately invalid: service fields, work variants and record-count policies are nominal types.
import ../../../src/codec/[composite, bounded]
let limit = ByteLimit(1)
let limits = PreimageLimits(items: limit)
discard limits
