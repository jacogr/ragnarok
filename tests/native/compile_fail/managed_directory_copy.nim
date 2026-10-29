# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stable directory locks cannot be duplicated during ARC lowering.
# @@Verification={"group":"ownership_compile","build_name":"managed-directory-copy","expected":"'=dup' is not available for type <ManagedDirectory>"}
import ../../../src/storage/managed/io as managed_io
proc duplicated(source: ManagedDirectory): ManagedDirectory =
  ## Returning a borrowed native owner would duplicate lock retirement authority.
  source
var first = default(ManagedDirectory)
var second = duplicated(first)
discard first.opened
discard second.close
