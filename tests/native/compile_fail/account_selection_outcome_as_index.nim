# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"AccumulationAccountSelectionIndex","early":["selectedAccountAt(","[2] expected: AccumulationAccountSelectionIndex but got: AccumulationAnnulmentIndex"]}

## A producer-outcome ordinal cannot substitute a requested-account row ordinal.
import ../../../src/state/accumulation/account/selection as accumulation_account_selection
import ../../../src/state/accumulation/annulment as accumulation_annulment
discard selectedAccountAt(default(PreparedAccumulationAccountSelection), AccumulationAnnulmentIndex(0))
