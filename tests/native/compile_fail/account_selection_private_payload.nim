# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"privacy","expected":"completed"}

## Account-source selection and failed result storage remain private to their immutable owners.
import ../../../src/state/accumulation/account/selection as accumulation_account_selection
import ../../../src/state/accumulation/annulment as accumulation_annulment
let refused = prepareAccumulationAccountSelection(default(PreparedAccumulationAnnulment), [],
    default(AccumulationAccountSelectionLimits))
discard refused.completed
