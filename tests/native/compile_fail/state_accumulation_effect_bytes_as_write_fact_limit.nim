# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"ElementLimit","early":["prepareAccumulationEffects(","[6] expected: ElementLimit but got: ByteLimit"]}

## Physical fact ordinals and capacities cannot borrow another protocol unit.
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/state/accumulation_context as state_accumulation_context
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts

discard prepareAccumulationEffects(default(PreparedAccumulationContexts), ElementLimit(0),
    ElementLimit(0), ElementLimit(0), ElementLimit(0), ByteLimit(1))
