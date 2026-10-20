# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject public result forgery, source rebinding and mixed report retention domains.

# @@Verification={"group": "nominal", "expected": "got: ByteLimit but wanted: ElementLimit"}

import ../../../src/state/refinement_report
import ../../../src/codec/bounded
discard RefinementReportLimits(exports: ByteLimit(1))
