# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject composition result forgery, source replacement and mixed independent retention domains.

# @@Verification={"group": "nominal", "expected": "got: ByteLimit but wanted: FetchTraceLimit"}

import ../../../src/state/authorized_refinement as state_authorized_refinement
import ../../../src/codec/bounded as codec_bounded
discard AuthorizedRefinementLimits(trace: ByteLimit(1))
