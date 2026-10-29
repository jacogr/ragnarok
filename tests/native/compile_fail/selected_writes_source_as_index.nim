# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"expected: AccumulationSelectedWriteIndex but got: PreparedAccumulationAccountSelection","early":["selectedWriteAt(","[2] expected: AccumulationSelectedWriteIndex but got: PreparedAccumulationAccountSelection"]}

## Physical descriptor positions and fact counts cannot alias source owners or bytes.
import ../../../src/state/accumulation/selected_writes as accumulation_selected_writes
import ../../../src/state/accumulation/account/selection as accumulation_account_selection
import ../../../src/codec/bounded
discard selectedWriteAt(default(PreparedSelectedAccountWrites), default(PreparedAccumulationAccountSelection))
