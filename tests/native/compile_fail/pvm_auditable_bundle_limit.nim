# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A protocol E4 bundle length cannot substitute for local byte-allocation policy.

# @@Verification={"group": "nominal", "expected": "ByteLimit", "early": ["prepareAuditableBundle(", "[2] expected: ByteLimit but got: BundleLength"]}

import ../../../src/state/[auditable_bundle, input_refinement]
import ../../../src/codec/work_report
discard prepareAuditableBundle(default(InputRefinement), BundleLength(4096))
