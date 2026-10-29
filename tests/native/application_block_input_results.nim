# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused reception results expose no generation, successor or unselected failed child.

import std/cmdline
import "../../src/app/block/input" as block_input
import ../../src/app/[chain, candidate]
import ../../src/codec/bounded

var input = default(BlockInput)
let argument = paramStr(1)
let outcome = if argument == "default": default(BlockInputResult)
  else: input.prepare(default(BlockInputId), default(ApplicationChain))
let admission = if argument == "admission-default": default(BlockInputAdmission)
  else: input.begin(default(ApplicationChain), ByteLimit(1), [], default(BlockInputLimits),
    default(ApplicationCandidateLimits))
case argument
of "admission-default": discard admission.value # Defaults cannot authorize any callback.
of "admission-refused":
  discard admission.value # Missing heads cannot provide generations.
of "codec": discard outcome.decodeFailure # Default is not selected DecodeFailure.
of "preparation": discard outcome.preparationFailure # Default contains no failed producer child.
of "ancestors": discard outcome.ancestorDemand # Only explicit NeedsAncestors carries a discovery plan.
of "enqueue": discard outcome.enqueueError # Default has no failed handoff cause.
of "refused": discard outcome.value # Stale generation exposes no value.
else: discard outcome.value # Default contains no finalized certificate.
