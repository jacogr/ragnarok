# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentChainUpdate but got: PreparedChainUpdate", "early": ["handoff.(enqueue,", "[3] expected: PreparedCurrentChainUpdate but got: PreparedChainUpdate"]}

## Legacy prepared updates are not current sequence/state completion proof.
import ../../../src/app/[chain, current_handoff]
import ../../../src/state/accumulation_publication
var handoff = default(CurrentAccumulationHandoff)
discard handoff.enqueue(default(ApplicationChain), default(PreparedChainUpdate))
