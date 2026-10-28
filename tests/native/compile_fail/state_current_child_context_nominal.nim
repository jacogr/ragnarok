# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Mutable copied child facts cannot substitute authenticated current update provenance.
# @@Verification={"group":"nominal","expected":"PreparedCurrentChainUpdate","early":["captureCurrentProfile(","[1] expected: PreparedCurrentChainUpdate but got: BlockSnapshotContext"]}
import ../../../src/state/current_profile as state_current_profile
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/chain/genesis as chain_genesis
discard captureCurrentProfile(default(BlockSnapshotContext), CurrentProfileLimits())
