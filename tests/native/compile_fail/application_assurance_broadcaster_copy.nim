# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copying an assurance broadcaster could collect another owner's canonical lease or retire its native demand and request tokens.
# @@Verification={"group":"ownership_compile","build_name":"application-assurance-broadcaster-copy","expected":"'=dup' is not available for type <AssuranceBroadcaster>","rationale":"The stable optional CE141 broadcaster owns exact worker, request and physical dial tokens; an aggregate copy could collect or retire live resources still owned by its original.","reference":"spec/jamnp-assurance-lifecycle.md"}
import ../../../src/app/assurance_broadcast
proc duplicated(source: AssuranceBroadcaster): AssuranceBroadcaster =
  ## ARC lowering must reject the stable composite itself, independently of whether its opaque children happen to be copyable.
  source
var first = default(AssuranceBroadcaster)
var second = duplicated(first)
discard first.phase
discard second.phase
