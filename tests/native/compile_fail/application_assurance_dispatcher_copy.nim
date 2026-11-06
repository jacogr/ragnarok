# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Duplicating the composite receipt controller could cancel/join the original exact worker lease and retire its claimed native request.
# @@Verification={"group":"ownership_compile","build_name":"application-assurance-dispatcher-copy","expected":"'=dup' is not available for type <AssuranceDispatcher>","rationale":"The stable CE141 controller owns exact native and canonical-worker tokens; an aggregate copy could acknowledge, cancel or join work still owned by the original controller.","reference":"spec/jamnp-assurance-lifecycle.md"}
import ../../../src/app/assurance_distribution
proc duplicated(source: AssuranceDispatcher): AssuranceDispatcher =
  ## Actual ARC return lowering must reject the composite itself, independently of its copied opaque token children.
  source
var first = default(AssuranceDispatcher)
var second = duplicated(first)
discard first.pendingCount
discard second.pendingCount
