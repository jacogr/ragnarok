# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached source/map or substituted count/index domains.

# @@Verification={"group": "nominal","expected": "openArray","early": ["prepareComputedLinks(","[2] expected: openArray[ComputedWorkReport] but got: seq[SegmentLookup]"]}

import ../../../src/state/computed_links as state_computed_links
import ../../../src/state/computed_guarantee as state_computed_guarantee
import ../../../src/state/computed_report as state_computed_report
import ../../../src/state/report_identity as state_report_identity
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/work_report as codec_work_report
import ../../../src/pvm/host_fetch as pvm_host_fetch
discard prepareComputedLinks(default(ComputedGuaranteeTranscript), default(seq[SegmentLookup]),
    ElementLimit(1))
