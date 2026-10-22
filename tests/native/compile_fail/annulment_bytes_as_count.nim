# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"got: ByteLimit but wanted: ElementLimit"}

## Predicate checks count bounded operations, not a copied payload byte budget.
import ../../../src/state/accumulation_annulment
import ../../../src/codec/bounded
discard AccumulationAnnulmentLimits(checks: ByteLimit(1))
