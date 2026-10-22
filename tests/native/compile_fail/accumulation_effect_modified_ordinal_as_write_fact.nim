# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"AccumulationAccountWriteFactIndex","early":["effectAccountWriteFactAt(","[2] expected: AccumulationAccountWriteFactIndex but got: AccumulationModifiedAccountIndex"]}

## Physical fact ordinals and capacities cannot borrow another protocol unit.
import ../../../src/state/[accumulation_effects, accumulation_context]
import ../../../src/codec/[bounded, state_accounts]

discard effectAccountWriteFactAt(default(AccumulationEffectContext),
    AccumulationModifiedAccountIndex(0))
