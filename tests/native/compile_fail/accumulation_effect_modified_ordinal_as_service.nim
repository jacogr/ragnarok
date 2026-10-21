# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"ServiceIndex","early":["effectAccountModified(","[2] expected: ServiceIndex but got: AccumulationModifiedAccountIndex"]}

## Modification identity, ordinal and capacity units remain nominally distinct.
import ../../../src/state/[accumulation_effects, accumulation_context]
import ../../../src/codec/[bounded, state_accounts]

discard effectAccountModified(default(AccumulationEffectContext), AccumulationModifiedAccountIndex(0))
