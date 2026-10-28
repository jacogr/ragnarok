# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit full detached projection budgets include service/child descriptors and raw/payload bytes.
import ../../src/state/supplied_services as state_supplied_services
import ../../src/codec/bounded as codec_bounded
const suppliedServicesTestLimits* = SuppliedServicesLimits(services: ElementLimit(16),
    facts: ElementLimit(128), perValue: ByteLimit(65536), bytes: ByteLimit(262144))
