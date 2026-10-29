# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached package/execution artifacts as verified input sources.

# @@Verification={"group": "nominal", "expected": "VerifiedImportInputs", "early": ["runInputRefinement(", "[2] expected: VerifiedImportInputs but got: OwnedWorkPackage"]}

import ../../../src/state/[input_refinement, store]
import ../../../src/codec/work/report as work_report
import ../../../src/chain/parameters
import ../../../src/codec/work/package as work_package
discard runInputRefinement(default(StateStoreSnapshot), default(OwnedWorkPackage), CoreIndex(0),
    default(Parameters), default(InputRefinementLimits))
