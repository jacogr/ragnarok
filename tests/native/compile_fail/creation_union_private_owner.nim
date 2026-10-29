# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Creation union ownership and result storage stay private.
import ../../../src/state/accumulation/[creation_union as accumulation_creation_union,
    annulment as accumulation_annulment]
discard default(PreparedAccumulationCreationUnion).data
