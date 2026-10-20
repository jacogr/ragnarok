# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached source/map or substituted count/index domains.

# @@Verification={"group": "nominal", "expected": "openArray", "early": ["prepareComputedLinks(", "[2] expected: openArray but got: seq"]}

import ../../../src/state/[computed_links, computed_guarantee, computed_report, report_identity]
import ../../../src/codec/[bounded, work_report]
import ../../../src/pvm/host_fetch
discard prepareComputedLinks(default(ComputedGuaranteeTranscript), default(seq[SegmentLookup]),
    ElementLimit(1))
