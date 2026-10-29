# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External publication transitions require an admitted pending/current job, never a default slot.
import std/cmdline
import ../../src/app/current/handoff as current_handoff
import ../../src/app/chain
import ../../src/chain/genesis
var slot = default(CurrentAccumulationHandoff)
case paramStr(1)
of "mark": slot.markPublishing() # Idle cannot grant a publication lease.
else:
  let absent = default(ApplicationChainResult[BlockSnapshot])
  slot.completePublication(absent) # Idle has no expected installed child or external job.
