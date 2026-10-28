# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused reception results expose no generation, successor or unselected failed child.

import std/cmdline
import ../../src/app/current_block_input as app_current_block_input
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
import ../../src/codec/bounded as codec_bounded

var input = default(CurrentBlockInput)
let argument = paramStr(1)
let outcome = if argument == "default": default(CurrentBlockInputResult)
  else: input.prepare(default(CurrentBlockInputId), default(ApplicationChain))
let admission = if argument == "admission-default": default(CurrentBlockInputAdmission)
  else: input.begin(default(ApplicationChain), ByteLimit(1), [], default(CurrentBlockInputLimits),
    default(CurrentCandidateLimits))
case argument
of "admission-default": discard admission.value # Defaults cannot authorize any callback.
of "admission-refused":
  discard admission.value # Missing heads cannot provide generations.
of "codec": discard outcome.decodeFailure # Default is not selected DecodeFailure.
of "preparation": discard outcome.preparationFailure # Default contains no failed producer child.
of "ancestors": discard outcome.ancestorDemand # Only explicit NeedsAncestors carries a discovery plan.
of "enqueue": discard outcome.enqueueError # Default has no failed handoff cause.
of "refused": discard outcome.value # Stale generation exposes no value.
else: discard outcome.value # Default contains no prepared current update.
