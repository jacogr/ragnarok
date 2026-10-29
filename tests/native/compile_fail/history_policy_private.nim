# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"privacy","expected":"keep"}

## The zero/archive sentinel is available only through validated policy constructors.
import ../../../src/storage/history/index as history_index
let policy = default(HistoryPolicy)
discard policy.keep
