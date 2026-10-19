# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Defaults/refusals expose no recent history, source, prior, root, successor or unrelated failure reason.

import std/cmdline
import ../../src/state/[recent_history, ready_reconciliation]
let argument = paramStr(1)
let owner = default(PreparedRecentHistory)
let published = default(PublishedRecentHistory)
let outcome = if argument == "default": default(RecentHistoryResult[PreparedRecentHistory])
  else: prepareRecentHistory(default(PublishedReadyReconciliation), default(RecentHistoryConfig))
case argument
of "info": discard owner.recentHistoryInfo.value # No fabricated identities or observations.
of "source": discard owner.recentHistorySource.value # No synthesized post-ready source.
of "prior": discard owner.recentHistoryPrior.value # No default complete map.
of "entry": discard owner.recentHistoryEntry.value # No partial C(3).
of "snapshot": discard owner.recentHistorySnapshot.value # No fabricated empty history.
of "published-source": discard published.publishedRecentSource.value # No unverified preparation.
of "published-state": discard published.publishedRecentState.value # No partial successor.
of "codec-error": discard outcome.codecError # Invalid source selects no codec diagnosis.
of "crypto-error": discard outcome.cryptoError # No unrelated header-hash refusal.
of "output-error": discard outcome.outputError # No unselected output-tree refusal.
of "history-error": discard outcome.historyError # No fabricated belt/transition failure.
of "state-error": discard outcome.stateError # No unrelated publication diagnosis.
else: discard outcome.value # Both defaults and refusals require complete selected success.
