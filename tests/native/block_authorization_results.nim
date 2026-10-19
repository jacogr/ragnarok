# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Defaults/refusals expose no source-bound pool bytes, successor or unrelated failure reason.

import std/cmdline
import ../../src/state/[block_authorization, block_preimages, store]
let argument = paramStr(1)
let owner = default(PreparedBlockAuthorization)
let published = default(PublishedBlockAuthorization)
var state = default(StateStore)
let outcome = if argument == "default": default(BlockAuthorizationResult[PreparedBlockAuthorization])
  else: prepareBlockAuthorization(default(PublishedBlockPreimages), default(
      BlockAuthorizationConfig))
case argument
of "info": discard owner.blockAuthorizationInfo.value # Require the selected success/reason alternative.
of "source": discard owner.blockAuthorizationSource.value # Require the selected success/reason alternative.
of "prior": discard owner.blockAuthorizationPrior.value # Require the selected success/reason alternative.
of "entry": discard owner.blockAuthorizationEntry.value # Require the selected success/reason alternative.
of "published-source": discard published.publishedAuthorizationSource.value # Require the selected success/reason alternative.
of "published-state": discard published.publishedAuthorizationState.value # Require the selected success/reason alternative.
of "publish": discard publishBlockAuthorization(owner).value # Require the selected success/reason alternative.
of "advance": discard advanceBlockAuthorization(state,
    owner).value # Require the selected success/reason alternative.
of "codec-error": discard outcome.codecError # Require the selected success/reason alternative.
of "transition-error": discard outcome.transitionError # Require the selected success/reason alternative.
of "state-error": discard outcome.stateError # Require the selected success/reason alternative.
else: discard outcome.value # Both defaults and actual refusals require complete selected success.
