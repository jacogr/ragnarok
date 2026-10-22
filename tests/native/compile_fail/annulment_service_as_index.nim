# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"AccumulationAnnulmentIndex","early":["annulmentDecisionAt(","[2] expected: AccumulationAnnulmentIndex but got: ServiceIndex"]}

## An invoking service identity cannot substitute the source-outcome ordinal.
import ../../../src/state/accumulation_annulment
import ../../../src/codec/state_accounts
discard annulmentDecisionAt(default(PreparedAccumulationAnnulment), ServiceIndex(0))
