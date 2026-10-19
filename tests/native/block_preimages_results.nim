# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused source-bound preimage results expose no owner, counts, map or unrelated nested reason.

import std/cmdline
import ../../src/state/[block_preimages, recent_history, store]
let argument = paramStr(1)
let owner = default(PreparedBlockPreimages)
let published = default(PublishedBlockPreimages)
var state = default(StateStore)
let outcome = if argument == "default": default(BlockPreimageResult[PreparedBlockPreimages])
  else: prepareBlockPreimages(default(PublishedRecentHistory), default(BlockPreimageConfig))
case argument
of "info": discard owner.blockPreimageInfo.value # Require the selected success/reason alternative.
of "source": discard owner.blockPreimageSource.value # Require the selected success/reason alternative.
of "admission": discard owner.blockPreimageAdmission.value # Require the selected success/reason alternative.
of "prior": discard owner.blockPreimagePrior.value # Require the selected success/reason alternative.
of "published-source": discard published.publishedPreimageSource.value # Require the selected success/reason alternative.
of "published-state": discard published.publishedPreimageState.value # Require the selected success/reason alternative.
of "publish": discard publishBlockPreimages(owner).value # Require the selected success/reason alternative.
of "advance": discard advanceBlockPreimages(state, owner).value # Require the selected success/reason alternative.
of "preimage-error": discard outcome.preimageError # Require the selected success/reason alternative.
else: discard outcome.value # Defaults and actual refusals contain no completed payload.
