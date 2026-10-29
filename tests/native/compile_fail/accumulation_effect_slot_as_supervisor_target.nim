# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"ServiceIndex","early":["recordAccumulationSupervisor(","[2] expected: ServiceIndex but got: AccountSlot"]}

## An account creation slot cannot substitute the target service identity for reassignment.
import ../../../src/state/accumulation/effects as accumulation_effects
import ../../../src/codec/composite
import ../../../src/codec/state/accounts as state_accounts

discard recordAccumulationSupervisor(default(AccumulationEffects), AccountSlot(1), ServiceIndex(42))
