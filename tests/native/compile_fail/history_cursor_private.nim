# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"privacy","expected":"first"}

## Callers cannot rewrite a selected historical prefix or fabricate unpruned availability.
import ../../../src/storage/history/index as history_index
let cursor = default(HistoryCursor)
discard cursor.first
