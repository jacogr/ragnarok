# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"AnnulmentOutputIndex","early":["annulmentOutputAt(","[2] expected: AnnulmentOutputIndex but got: AccumulationAnnulmentIndex"]}

## Producer outcome ordinals cannot substitute selected service/hash pair ordinals.
import ../../../src/state/[accumulation_annulled_outputs, accumulation_annulment]
discard annulmentOutputAt(default(PreparedAnnulmentOutputs), AccumulationAnnulmentIndex(0))
