# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"privacy","expected":"data"}

## Account-source selection and failed result storage remain private to their immutable owners.
import ../../../src/state/[accumulation_account_selection, accumulation_annulment]
discard default(PreparedAccumulationAccountSelection).data
