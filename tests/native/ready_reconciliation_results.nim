# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Defaults/refusals expose no source, prior, queue, entry, successor or unrelated reason.

import std/cmdline
import ../../src/state/[ready_reconciliation, accumulation_publication]
let argument = paramStr(1)
let owner = default(PreparedReadyReconciliation)
let published = default(PublishedReadyReconciliation)
let outcome = if argument == "default": default(ReadyReconciliationResult[PreparedReadyReconciliation])
  else: prepareReadyReconciliation(default(PublishedAccumulation), default(
      ReadyReconciliationConfig))
case argument
of "info": discard owner.readyReconciliationInfo.value # No fabricated observations.
of "source": discard owner.readyReconciliationSource.value # No synthesized coordinated source.
of "prior": discard owner.readyReconciliationPrior.value # No default full map.
of "entry": discard owner.readyReconciliationEntry.value # No partial C(14).
of "queue": discard owner.readyReconciliationQueue.value # No fabricated empty queue.
of "published-source": discard published.publishedReadySource.value # No unverified preparation.
of "published-state": discard published.publishedReadyState.value # No partial successor.
of "codec-error": discard outcome.codecError # Invalid source selects no codec diagnosis.
of "state-error": discard outcome.stateError # No unrelated publication diagnosis.
else: discard outcome.value # Defaults and refusals require selected complete success.
