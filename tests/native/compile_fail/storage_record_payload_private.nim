# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local codec results must not expose mutable alternatives.
# @@Verification={"group":"privacy","expected":"completed"}
import ../../../src/storage/record_codec
import ../../../src/storage/node/records as node_records
let hidden = default(RecordResult[TrieExport])
discard hidden.completed
