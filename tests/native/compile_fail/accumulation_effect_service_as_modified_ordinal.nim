# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"AccumulationModifiedAccountIndex","early":["effectModifiedAccountAt(","[2] expected: AccumulationModifiedAccountIndex but got: ServiceIndex"]}

## Modification identity, ordinal and capacity units remain nominally distinct.
import ../../../src/state/accumulation/[effects as accumulation_effects,
    context as accumulation_context]
import ../../../src/codec/bounded
import ../../../src/codec/state/accounts as state_accounts

discard effectModifiedAccountAt(default(AccumulationEffectContext), ServiceIndex(42))
