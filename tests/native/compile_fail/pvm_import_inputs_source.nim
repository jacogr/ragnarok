# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare package cannot substitute for previously authenticated extrinsic ownership.

# @@Verification={"group":"nominal","expected":"VerifiedExtrinsics","early":["bindImportInputs(","[1] expected: VerifiedExtrinsics but got: OwnedWorkPackage"],"rationale":"bindImportInputs must demand original verified extrinsic ownership; accepting a bare work package would bypass authentication and original-package provenance before binding imported leaves.","reference":"src/state/import/inputs.nim"}

import "../../../src/state/import/inputs" as import_inputs
import ../../../src/codec/work/package as work_package
discard bindImportInputs(default(OwnedWorkPackage), [], [], default(ImportInputsLimits))
