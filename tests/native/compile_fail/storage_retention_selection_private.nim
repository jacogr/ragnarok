# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Retention plans must not expose mutable source or selected-position storage.
# @@Verification={"group": "privacy", "expected": "data"}
import ../../../src/storage/node/repository as node_repository
let plan = default(RepositorySelection)
discard plan.data
