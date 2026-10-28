# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Service indices cannot select the configured execution core.

# @@Verification={"group": "nominal", "expected": "CoreIndex", "early": ["runInputRefinement(", "[3] expected: CoreIndex but got: ServiceIndex"]}

import ../../../src/state/input_refinement as state_input_refinement
import ../../../src/state/import_inputs as state_import_inputs
import ../../../src/state/store as state_store
import ../../../src/codec/composite as codec_composite
import ../../../src/chain/parameters as chain_parameters
discard runInputRefinement(default(StateStoreSnapshot), default(VerifiedImportInputs), ServiceIndex(
    0), default(Parameters), default(InputRefinementLimits))
