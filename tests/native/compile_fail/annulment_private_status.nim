# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"privacy","expected":"status"}

## Annulment certificates and tagged result storage cannot be read or forged by callers.
import ../../../src/state/[accumulation_annulment, accumulation_inputs, store]
let refused = prepareAccumulationAnnulment(default(PreparedAccumulationInputs), default(
    StateStoreSnapshot), [], default(AccumulationAnnulmentLimits))
discard refused.status
