# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"AccumulationModifiedAccountIndex","early":["effectModifiedAccountAt(","[2] expected: AccumulationModifiedAccountIndex but got: ServiceIndex"]}

## Modification identity, ordinal and capacity units remain nominally distinct.
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/state/accumulation_context as state_accumulation_context
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts

discard effectModifiedAccountAt(default(AccumulationEffectContext), ServiceIndex(42))
