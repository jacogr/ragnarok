# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"expected: AccumulationSelectedWriteIndex but got: PreparedAccumulationAccountSelection","early":["selectedWriteAt(","[2] expected: AccumulationSelectedWriteIndex but got: PreparedAccumulationAccountSelection"]}

## Physical descriptor positions and fact counts cannot alias source owners or bytes.
import ../../../src/state/accumulation_selected_writes as state_accumulation_selected_writes
import ../../../src/state/accumulation_account_selection as state_accumulation_account_selection
import ../../../src/codec/bounded as codec_bounded
discard selectedWriteAt(default(PreparedSelectedAccountWrites), default(PreparedAccumulationAccountSelection))
