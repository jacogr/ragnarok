# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Disk ownership and selected result backing cannot escape the public lifecycle.
# @@Verification={"group":"privacy","expected":"descriptor"}
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/node/repository as node_repository
let hidden = default(FileRepository)
discard hidden.descriptor
