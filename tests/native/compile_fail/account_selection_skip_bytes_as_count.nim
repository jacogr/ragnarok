# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"got: ByteLimit but wanted: ElementLimit"}

## Non-executing source capture counts certified participants, not bytes.
import ../../../src/state/accumulation/account/selection as accumulation_account_selection
import ../../../src/codec/bounded
discard AccumulationAccountSelectionLimits(skipped: ByteLimit(1))
