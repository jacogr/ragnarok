# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"expected: AccumulationOutcome but got: AbsentAccumulation","early":["outcomeInfo(","[1] expected: AccumulationOutcome but got: AbsentAccumulation"]}

## Absent outcomes cannot alias protocol service ordinals or actual executed outcomes.
import ../../../src/state/accumulation/[absent as accumulation_absent,
    inputs as accumulation_inputs, outcome as accumulation_outcome]
import ../../../src/state/store
import ../../../src/codec/header
import ../../../src/codec/state/accounts as state_accounts
discard outcomeInfo(default(AbsentAccumulation))
