# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine admitted current blocks traverse the execution owner's existing private completion entry point.
import ./state_accumulation_current_chain_context
import ./state_accumulation_current_candidate_context
import ../../src/app/chain as app_chain
import ../../src/app/candidate as app_candidate
import ../../src/chain/provider as chain_provider
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/report_admission as state_report_admission
import ../../src/state/block_transition as state_block_transition
import ../../src/state/block_admission as state_block_admission
proc currentCheckpointPrepared*(context: CurrentChainFixture,
    finalized = true): PreparedCurrentChainUpdate =
  ## Preserve original parent/history/parameters and explicit finality; supply no replacement map to completion.
  let view = if finalized: context.currentChainSeeded else: genesisView(context.parent)
  let chain = initApplicationChain(view).value
  let child = context.source.currentChainAdmission.reportBlockStage.value.value.admitted.admittedBlock
  prepareCurrentCandidate(chain, child, [], currentCandidateLimits()).value
