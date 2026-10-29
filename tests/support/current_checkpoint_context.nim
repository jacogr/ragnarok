# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine admitted current blocks traverse the execution owner's existing private completion entry point.
import ./[accumulation_current_chain_context, accumulation_current_candidate_context]
import ../../src/app/[chain, candidate]
import ../../src/chain/provider
import ../../src/state/accumulation/current/update as accumulation_current_update
import ../../src/state/report/admission as report_admission
import "../../src/state/block/transition" as block_transition
import "../../src/state/block/admission" as block_admission
proc currentCheckpointPrepared*(context: CurrentChainFixture,
    finalized = true): PreparedCurrentChainUpdate =
  ## Preserve original parent/history/parameters and explicit finality; supply no replacement map to completion.
  let view = if finalized: context.currentChainSeeded else: genesisView(context.parent)
  let chain = initApplicationChain(view).value
  let child = context.source.currentChainAdmission.reportBlockStage.value.value.admitted.admittedBlock
  prepareCurrentCandidate(chain, child, [], currentCandidateLimits()).value
