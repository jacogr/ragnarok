# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Creation union ownership and result storage stay private.
import ../../../src/state/accumulation_creation_union as state_accumulation_creation_union
import ../../../src/state/accumulation_annulment as state_accumulation_annulment
discard default(PreparedAccumulationCreationUnion).data
