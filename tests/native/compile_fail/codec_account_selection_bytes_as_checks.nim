# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"got: ByteLimit but wanted: ElementLimit"}

## Account-source selection predicate checks count operations, not payload bytes.
import ../../../src/state/accumulation_account_selection as state_accumulation_account_selection
import ../../../src/codec/bounded as codec_bounded
discard AccumulationAccountSelectionLimits(checks: ByteLimit(1))
