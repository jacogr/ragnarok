# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached source/map or substituted count/index domains.

# @@Verification={"group": "nominal", "expected": "ReportLookupIndex", "early": ["computedLinkWitness(", "[2] expected: ReportLookupIndex but got: FetchItemIndex"]}

import ../../../src/state/[computed_links, computed_guarantee, computed_report, report_identity]
import ../../../src/codec/[bounded, work_report]
import ../../../src/pvm/host_fetch
discard computedLinkWitness(default(ComputedReportLinks), FetchItemIndex(0))
