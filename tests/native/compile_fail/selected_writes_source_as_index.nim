# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: AccumulationSelectedWriteIndex but got: PreparedAccumulationAccountSelection"}

## Physical descriptor positions and fact counts cannot alias source owners or bytes.
import ../../../src/state/[accumulation_selected_writes, accumulation_account_selection]
import ../../../src/codec/bounded
discard default(PreparedSelectedAccountWrites).selectedWriteAt(default(PreparedAccumulationAccountSelection))
