# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"ServiceIndex","early":["recordAccumulationSupervisor(","[2] expected: ServiceIndex but got: AccountSlot"]}

## An account creation slot cannot substitute the target service identity for reassignment.
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/state_accounts as codec_state_accounts

discard recordAccumulationSupervisor(default(AccumulationEffects), AccountSlot(1), ServiceIndex(42))
