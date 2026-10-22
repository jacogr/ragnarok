# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Refused/default timestamp owners expose no selected state or mismatched reason.
import std/cmdline
import ../../src/state/[accumulation_current_accounts, accumulation_accounts,
    accumulation_current_statistics]
let owner = default(CurrentAccumulationAccountResult[PreparedCurrentAccumulationAccounts])
let accounts = default(PreparedCurrentAccumulationAccounts)
let refused = prepareCurrentAccumulationAccounts(default(PreparedCurrentAccumulationStatistics),
    default(AccumulationAccountConfig))
case paramStr(1)
of "refused": discard refused.value # No state survives source refusal.
of "info": discard accounts.currentAccountsInfo.value # No default observations.
of "source": discard accounts.currentAccountsSource.value # No synthetic statistics graph.
of "state": discard accounts.currentAccountsState.value # No default private map.
of "projection": discard refused.projectionFailure # Only selected projection failures carry this reason.
of "backend": discard refused.stateFailure # Only selected backend failures carry this reason.
else: discard owner.value # Default result is uninitialized.
