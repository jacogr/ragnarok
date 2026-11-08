# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copying an acquisition controller could collect another owner's canonical lease or retire its native demand and request tokens.

# @@Verification={"group":"ownership_compile","build_name":"application-assurance-acquirer-copy","expected":"'=dup' is not available for type <AssuranceAcquirer>","rationale":"The stable optional CE137 controller owns exact worker, request and physical dial tokens; an aggregate copy could collect or retire live resources still owned by its original.","reference":"spec/jamnp-assurance-lifecycle.md"}
import ../../../src/app/assurance_acquirer

proc duplicated(source: AssuranceAcquirer): AssuranceAcquirer =
  ## ARC lowering must reject the stable composite itself, independently of whether its opaque children happen to be copyable.
  source
var first = default(AssuranceAcquirer)
var second = duplicated(first)
discard first.phase
discard second.phase
