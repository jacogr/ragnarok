# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"ElementLimit","early":["prepareAccumulationEffects(","[5] expected: ElementLimit but got: ByteLimit"]}

## Modification identity, ordinal and capacity units remain nominally distinct.
import ../../../src/state/accumulation/[effects as accumulation_effects,
    context as accumulation_context]
import ../../../src/codec/bounded
import ../../../src/codec/state/accounts as state_accounts

discard prepareAccumulationEffects(default(PreparedAccumulationContexts), ElementLimit(0),
    ElementLimit(0), ElementLimit(0), ByteLimit(1))
