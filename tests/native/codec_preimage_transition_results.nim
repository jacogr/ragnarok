# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict selected-success misuse probes for admitted preimages, source identity and atomic publication.
## Dynamic modes must fail contracts instead of supplying default state/counts after refusal.

import std/cmdline
import ../../src/state/preimages as state_preimages
import ../../src/state/store as state_store
import ../../src/codec/owned as codec_owned
import ../../src/codec/composite as codec_composite
import ../../src/codec/header as codec_header

# Runtime selection retains an actual admission refusal without compile-time invalid extraction.
let outcome = if paramStr(1) == "refused":
  admitPreimages(default(StateStoreSnapshot), default(OwnedFrame), default(PreimageLimits))
else: default(PreimageTransitionResult[AdmittedPreimages]) # No completed payload exists.
let plan = default(AdmittedPreimages)
var state = default(StateStore)
case paramStr(1)
of "info": discard plan.preimageInfo.value # Default certificates cannot supply successful observations.
of "prior": discard plan.preimagePrior.value # Default certificates cannot supply successful observations.
of "source": discard plan.preimageSource.value # Default certificates cannot supply successful observations.
of "provision": discard plan.provisionAt(ProvisionIndex(
    0)).value # Default certificates cannot supply successful observations.
of "publish": discard integratePreimages(state, plan, HeaderSlot(
    0)).value # Default certificates cannot supply successful observations.
else: discard outcome.value # Both actual and default refusal are selected-success guarded.
