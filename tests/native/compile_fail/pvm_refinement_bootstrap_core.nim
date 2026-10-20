# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Package item indices cannot silently replace the nominal core selection.

# @@Verification={"group": "nominal", "expected": "CoreIndex", "early": ["prepareRefinementBootstrap(", "[4] expected: CoreIndex but got: FetchItemIndex"]}

import ../../../src/state/[refinement_bootstrap, store]
import ../../../src/pvm/host_fetch
import ../../../src/codec/work_package
import ../../../src/chain/parameters
discard prepareRefinementBootstrap(default(StateStoreSnapshot), default(OwnedWorkPackage),
  FetchItemIndex(0), FetchItemIndex(0), default(Parameters), default(RefinementBootstrapLimits))
