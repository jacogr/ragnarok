# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"privacy","expected":"applicationReason"}

## The chain result cannot be retagged or expose its private successful/failed payload storage.

import ../../../src/state/accumulation_chain as state_accumulation_chain
var outcome = default(AccumulationChainResult)
discard outcome.applicationReason
