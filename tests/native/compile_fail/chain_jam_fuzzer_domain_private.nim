# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## An ordinary consumer cannot erase the immutable fuzz seed domain through a public view.
# @@Verification={"group": "privacy", "expected": "fuzzOrigin"}
import ../../../src/chain/provider as chain_provider
let view = default(ChainView)
discard view.fuzzOrigin
