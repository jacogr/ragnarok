# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The complete assurance namespace owner must reject duplication during actual ARC lowering.

# @@Verification={"group":"ownership_compile","build_name":"assurance-store-copy","expected":"'=dup' is not available for type <AssuranceStore>","rationale":"A copied composite would duplicate one live advisory writer lease while its disk/count clocks diverged, allowing either alias to release single-writer exclusion or publish against stale capacity. The child writer hook alone does not establish the composite contract.","reference":"spec/jamnp-assurance-lifecycle.md"}
import ../../../src/jamnp-s/assurance_store

proc duplicate(source: AssuranceStore): AssuranceStore =
  ## Returning a borrowed native writer would give two owners the same lease and directory lifetime.
  source
var first = default(AssuranceStore)
var second = duplicate(first)
discard first.opened
discard second.close()
