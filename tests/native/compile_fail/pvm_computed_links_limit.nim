# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached source/map or substituted count/index domains.

# @@Verification={"group": "nominal", "expected": "ElementLimit", "early": ["prepareComputedLinks(", "[3] expected: ElementLimit but got: ByteLimit"]}

import ../../../src/state/[computed_links, computed_guarantee, computed_report, report_identity]
import ../../../src/codec/[bounded, work_report]
import ../../../src/pvm/host_fetch
discard prepareComputedLinks(default(ComputedGuaranteeTranscript), [], ByteLimit(1))
