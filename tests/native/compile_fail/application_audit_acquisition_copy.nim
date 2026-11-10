# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Duplicating acquisition could cancel another owner's original private evaluation or live native retrieval.

# @@Verification={"group":"ownership_compile","build_name":"application-audit-acquisition-copy","expected":"'=dup' is not available for type <AuditAcquisition>","rationale":"The CE147/138 composite retains exact native request/dial and private Services worker controls through cancellation and Done; duplication could retire another acquisition's live resources.","reference":"spec/jamnp-audit-runtime.md"}
import ../../../src/app/audit_acquisition

proc duplicated(source: AuditAcquisition): AuditAcquisition =
  ## Lowering must reject the owning composite rather than relying on field-level token checks.
  source
var first = default(AuditAcquisition)
var second = duplicated(first)
discard first.phase
discard second.phase
