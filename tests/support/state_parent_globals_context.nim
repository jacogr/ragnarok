# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit whole-global policies accompany independent view/C9 admission for selected parent consumers.
import ../../src/state/global_snapshot as state_global_snapshot
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_composition as codec_state_composition
const parentGlobalsTestLimits* = GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(
    10000), maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))
