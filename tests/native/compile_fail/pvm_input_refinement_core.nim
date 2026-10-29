# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Service indices cannot select the configured execution core.

# @@Verification={"group": "nominal", "expected": "CoreIndex", "early": ["runInputRefinement(", "[3] expected: CoreIndex but got: ServiceIndex"]}

import ../../../src/state/input_refinement
import "../../../src/state/import/inputs" as import_inputs
import ../../../src/state/store
import ../../../src/codec/composite
import ../../../src/chain/parameters
discard runInputRefinement(default(StateStoreSnapshot), default(VerifiedImportInputs), ServiceIndex(
    0), default(Parameters), default(InputRefinementLimits))
