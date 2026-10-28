# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject public result forgery, source rebinding and mixed report retention domains.

# @@Verification={"group": "nominal", "expected": "got: ByteLimit but wanted: ElementLimit"}

import ../../../src/state/refinement_report as state_refinement_report
import ../../../src/codec/bounded as codec_bounded
discard RefinementReportLimits(exports: ByteLimit(1))
