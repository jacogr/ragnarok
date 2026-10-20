# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Disk ownership and selected result backing cannot escape the public lifecycle.
# @@Verification={"group":"privacy","expected":"descriptor"}
import ../../../src/storage/[file_repository, node_repository]
let hidden = default(FileRepository)
discard hidden.descriptor
