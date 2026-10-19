# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Defaults/refusals expose no batch, source, prior, successor or unrelated nested failure reason.

import std/cmdline
import ../../src/state/[accumulation_publication, block_activity]
let argument = paramStr(1)
let owner = default(PreparedAccumulationPublication)
let published = default(PublishedAccumulation)
let outcome = if argument == "default": default(AccumulationPublicationResult[PreparedAccumulationPublication])
  else: prepareAccumulationPublication(default(PreparedBlockActivity), default(
      AccumulationPublicationConfig))
case argument
of "info": discard owner.accumulationPublicationInfo.value # No fabricated observations.
of "source": discard owner.accumulationPublicationSource.value # No synthesized complete activity owner.
of "prior": discard owner.accumulationPublicationPrior.value # No default complete map.
of "write": discard owner.accumulationPublicationWrite(PublicationWriteIndex(0)).value # No partial batch.
of "published-source": discard published.publishedAccumulationSource.value # No unverified preparation.
of "published-state": discard published.publishedAccumulationState.value # No partial successor.
of "account-error": discard outcome.accountError # Invalid source does not select account failure.
of "metadata-error": discard outcome.metadataError # No unrelated metadata diagnosis.
of "history-error": discard outcome.historyError # No unrelated history producer reason.
of "history-codec-error": discard outcome.historyCodecError # No unselected codec reason.
of "state-error": discard outcome.stateError # No fabricated atomic publication reason.
else: discard outcome.value # Both default and invalid-source extraction require selected success.
