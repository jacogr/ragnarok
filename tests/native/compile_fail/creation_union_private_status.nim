# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Creation union ownership and result storage stay private.
import ../../../src/state/[accumulation_creation_union, accumulation_annulment]
let refused = prepareAccumulationCreationUnion(default(PreparedAccumulationAnnulment), default(
    AccumulationCreationLimits))
discard refused.status
