# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frame transport results hide successful bytes and selected error causes.
# @@Verification={"group":"privacy","expected":"recordReason"}
import ../../../src/storage/journal_codec as storage_journal_codec
let hidden = default(FrameResult[JournalFrame])
discard hidden.recordReason
