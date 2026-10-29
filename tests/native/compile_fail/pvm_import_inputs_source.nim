# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare package cannot substitute for previously authenticated extrinsic ownership.

# @@Verification={"group": "nominal", "expected": "VerifiedExtrinsics", "early": ["bindImportInputs(", "[1] expected: VerifiedExtrinsics but got: OwnedWorkPackage"]}

import "../../../src/state/import/inputs" as import_inputs
import ../../../src/codec/work/package as work_package
discard bindImportInputs(default(OwnedWorkPackage), [], [], default(ImportInputsLimits))
