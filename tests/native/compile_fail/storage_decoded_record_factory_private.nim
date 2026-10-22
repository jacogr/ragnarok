# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot construct or access private encoded-admission authority.
# @@Verification={"group":"privacy","expected":"storeDecodedRecord"}
import ../../../src/storage/[node_repository, node_records]
var raw = default(TrieRecord)
discard node_repository.storeDecodedRecord(raw)
