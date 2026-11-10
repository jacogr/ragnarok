# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copying a pending audit controller could collect or cancel the original owner's native request and exact shared canonical lease.

# @@Verification={"group":"ownership_compile","build_name":"application-audit-dispatcher-copy","expected":"'=dup' is not available for type <AuditDispatcher>","rationale":"The optional CE144 controller owns exact native request and shared-worker tokens through Done and cancellation; copying the composite could retire another controller's live resources.","reference":"spec/jamnp-audit-runtime.md"}
import ../../../src/app/audit_distribution

proc duplicated(source: AuditDispatcher): AuditDispatcher =
  ## ARC lowering rejects the owning composite itself, independently of its token fields and immutable pool children.
  source
var first = default(AuditDispatcher)
var second = duplicated(first)
discard first.pendingCount
discard second.pendingCount
