# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused account timestamp results cannot expose successor state, sources or unrelated nested reasons.

import std/cmdline
import ../../src/state/accumulation/[accounts as accumulation_accounts,
    statistics as accumulation_statistics]

let argument = paramStr(1)
let owner = default(PreparedAccumulationAccounts)
let outcome = if argument == "default": default(AccumulationAccountResult[PreparedAccumulationAccounts])
  else: prepareAccumulationAccounts(default(PreparedAccumulationStatistics), default(
      AccumulationAccountConfig))
case argument
of "info": discard owner.accumulationAccountInfo.value # Defaults carry no authenticated slot or progress.
of "source": discard owner.accumulationAccountSource.value # Defaults cannot fabricate finalized statistics.
of "state": discard owner.accumulationAccountState.value # Defaults expose no successor snapshot.
of "wrong-metadata": discard outcome.metadataError # InvalidSource carries no metadata decoder reason.
of "wrong-state": discard outcome.stateError # InvalidSource carries no store failure.
else: discard outcome.value # Both default and refused preparation require selected success.
