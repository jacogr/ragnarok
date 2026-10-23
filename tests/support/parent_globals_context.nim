# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit whole-global policies accompany independent view/C9 admission for selected parent consumers.
import ../../src/state/global_snapshot
import ../../src/codec/[bounded, state_composition]
const parentGlobalsTestLimits* = GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(
    10000), maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))
