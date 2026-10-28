# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"privacy","expected":"status"}

## Selected yield certificates and failed tagged storage cannot be read or forged by callers.
import ../../../src/state/accumulation_annulled_outputs as state_accumulation_annulled_outputs
import ../../../src/state/accumulation_annulment as state_accumulation_annulment
let refused = prepareAnnulmentOutputs(default(PreparedAccumulationAnnulment), default(
    AnnulmentOutputLimits))
discard refused.status
