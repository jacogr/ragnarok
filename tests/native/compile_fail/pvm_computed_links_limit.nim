# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached source/map or substituted count/index domains.

# @@Verification={"group": "nominal", "expected": "ElementLimit", "early": ["prepareComputedLinks(", "[3] expected: ElementLimit but got: ByteLimit"]}

import ../../../src/state/computed/[links as computed_links, guarantee as computed_guarantee,
    report as computed_report]
import ../../../src/state/report/identity as report_identity
import ../../../src/codec/bounded
import ../../../src/codec/work/report as work_report
import ../../../src/pvm/host/fetch as host_fetch
discard prepareComputedLinks(default(ComputedGuaranteeTranscript), [], ByteLimit(1))
