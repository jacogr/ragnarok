# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"privacy","expected":"data"}

## Annulment certificates and tagged result storage cannot be read or forged by callers.
import ../../../src/state/accumulation_annulment as state_accumulation_annulment
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/store as state_store
discard default(PreparedAccumulationAnnulment).data
