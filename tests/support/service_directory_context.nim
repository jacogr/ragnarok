# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit descriptor and comparison bounds support complete source-bound service query fixtures.
import ../../src/state/service_directory
import ../../src/codec/bounded
const directoryTestLimits* = ServiceDirectoryLimits(services: ElementLimit(16),
    comparisons: ElementLimit(120), bytes: ByteLimit(4096))
