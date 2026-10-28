# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copying the composite file descriptor/lock owner must fail actual ARC lowering.
# @@Verification={"group":"ownership_compile","build_name":"storage-file-copy","expected":"'=dup' is not available for type <FileRepository>"}
import ../../../src/storage/file_repository as storage_file_repository
proc duplicated(source: FileRepository): FileRepository =
  ## Returning a borrowed source requires forbidden ownership duplication.
  source
var first = default(FileRepository)
var second = duplicated(first)
discard first.opened
discard second.close
