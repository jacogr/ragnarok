# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Defaults and failures cannot expose complete C(13), a source graph, profile or published map.

import std/cmdline
import ../../src/state/block_activity as state_block_activity
import ../../src/state/service_activity as state_service_activity
let argument = paramStr(1)
let owner = default(PreparedBlockActivity)
let published = default(PublishedBlockActivity)
let outcome = if argument == "default": default(BlockActivityResult[PreparedBlockActivity])
  else: prepareBlockActivity(default(PreparedServiceActivity), default(BlockActivityConfig))
case argument
of "info": discard owner.blockActivityInfo.value # Default owner has no output cardinalities.
of "source": discard owner.blockActivitySource.value # No synthesized service provenance.
of "entry": discard owner.blockActivityEntry.value # No fabricated empty C(13).
of "profile": discard owner.blockActivityProfile.value # No caller-selected profile on an uninitialized owner.
of "published-source": discard published.publishedActivitySource.value # No preparation certificate after default publication.
of "published-state": discard published.publishedActivityState.value # No partial map after failed publication.
of "core-error": discard outcome.coreError # An invalid source is not a core producer refusal.
of "validator-error": discard outcome.validatorError # No unrelated failure reason extraction.
of "codec-error": discard outcome.codecError # No fabricated encoding diagnostic.
of "state-error": discard outcome.stateError # No fabricated publication diagnostic.
else: discard outcome.value # Both default and invalid source extraction require selected success.
