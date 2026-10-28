# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit selected-view retention and independent C9 decode ceilings for genuine signed parent fixtures.
import ../../src/state/parent_profile as state_parent_profile
import ../../src/codec/bounded as codec_bounded
const parentProfileTestLimits* = ParentProfileLimits(blocks: ElementLimit(9),
    validators: ElementLimit(1024), viewBytes: ByteLimit(8388608), previousBytes: ByteLimit(65536))
