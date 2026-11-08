# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The ordinary application node owns every native callback and exact managed acquisition token through joined shutdown.

# @@Verification={"group":"ownership_compile","build_name":"application-node-copy","expected":"'=dup' is not available for type <ApplicationNode>","rationale":"The ordinary host is a stable native callback owner borrowing Services; duplication of its owning composite could double-cancel active retrieval/evaluation jobs or retire callbacks before native close.","reference":"spec/jamnp-audit-runtime.md"}
import ../../../src/app/node

proc duplicated(source: ApplicationNode): ApplicationNode =
  ## ARC lowering must reject the composite even if no particular child is active in this positive initialization control.
  source
var first = default(ApplicationNode)
var second = duplicated(first)
discard first.auditAcquisitionPhase
discard second.auditAcquisitionPhase
