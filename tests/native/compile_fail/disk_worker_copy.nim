# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Composite native disk worker duplication must fail actual ARC lowering.
# @@Verification={"group":"ownership_compile","build_name":"disk-worker-copy","expected":"'=dup' is not available for type <DiskPublicationWorker>","rationale":"Returning a borrowed disk worker would duplicate synchronization state and a native thread that retains the original worker address; closing either alias could race the live borrower.","reference":"src/app/disk/worker.nim"}
import ../../../src/app/disk/worker as disk_worker
proc duplicated(source: DiskPublicationWorker): DiskPublicationWorker =
  ## Returning a borrowed thread owner would duplicate locks and a fixed-address native borrower.
  source
var first = default(DiskPublicationWorker)
var second = duplicated(first)
discard first.phase
discard second.close
