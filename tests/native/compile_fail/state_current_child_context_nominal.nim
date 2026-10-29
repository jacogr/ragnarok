# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Mutable copied child facts cannot substitute authenticated current update provenance.
# @@Verification={"group":"nominal","expected":"PreparedCurrentChainUpdate","early":["captureCurrentProfile(","[1] expected: PreparedCurrentChainUpdate but got: BlockSnapshotContext"]}
import ../../../src/state/current/profile as current_profile
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/chain/genesis
discard captureCurrentProfile(default(BlockSnapshotContext), CurrentProfileLimits())
