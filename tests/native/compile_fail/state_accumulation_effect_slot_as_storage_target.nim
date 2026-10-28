# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"ServiceIndex","early":["recordAccumulationStorage(","[6] expected: ServiceIndex but got: AccountSlot"]}

## Account creation time cannot select a storage namespace in place of its nominal service ID.
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/chain/parameters as chain_parameters

discard recordAccumulationStorage(default(AccumulationEffects), @[1'u8], @[2'u8], default(
    Parameters), ByteLimit(1), AccountSlot(0))
