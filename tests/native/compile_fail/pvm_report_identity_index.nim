# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject item/lookup ordinal substitution before narrowing.

# @@Verification={"group": "nominal", "expected": "ReportLookupIndex", "early": ["identityLookupAt(", "[2] expected: ReportLookupIndex but got: FetchItemIndex"]}

import ../../../src/state/report/identity as report_identity
import ../../../src/pvm/host_fetch
discard identityLookupAt(default(ReportIdentity), FetchItemIndex(0))
