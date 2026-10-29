# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Only original input-bound execution can authorize auditable bundle assembly.

# @@Verification={"group": "nominal", "expected": "InputRefinement", "early": ["prepareAuditableBundle(", "[1] expected: InputRefinement but got: VerifiedImportInputs"]}

import ../../../src/state/auditable_bundle
import "../../../src/state/import/inputs" as import_inputs
import ../../../src/codec/bounded
discard prepareAuditableBundle(default(VerifiedImportInputs), ByteLimit(4096))
