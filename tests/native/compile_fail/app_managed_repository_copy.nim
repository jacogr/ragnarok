# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed repository duplication must fail actual native lowering.
# @@Verification={"group":"ownership_compile","build_name":"managed-repository-copy","expected":"'=dup' is not available for type <ManagedRepository>"}
import ../../../src/storage/managed_repository as storage_managed_repository
proc duplicated(source: ManagedRepository): ManagedRepository =
  ## A borrowed append owner cannot acquire another retirement authority.
  source
var first = default(ManagedRepository)
var second = duplicated(first)
discard first.opened
discard second.close
