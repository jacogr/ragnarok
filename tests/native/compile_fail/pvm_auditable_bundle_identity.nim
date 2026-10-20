# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Only original input-bound execution can authorize auditable bundle assembly.

# @@Verification={"group": "nominal", "expected": "InputRefinement", "early": ["prepareAuditableBundle(", "[1] expected: InputRefinement but got: ReportIdentity"]}

import ../../../src/state/[auditable_bundle, report_identity]
import ../../../src/codec/bounded
discard prepareAuditableBundle(default(ReportIdentity), ByteLimit(4096))
