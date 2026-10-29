# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently authored original guest modes reach real assured queues and retain canonical predecessor handles.

import std/assertions
import ../../src/state/computed/chain as computed_chain
import ../../src/state/computed/state/publication as computed_state_publication
import ../../src/state/computed/[composition as computed_composition,
    finalization as computed_finalization, execution as computed_execution,
    assurances as computed_assurances]
import ../../src/state/assured/queue as assured_queue
import ../../src/state/accumulation/execution as accumulation_execution
import ../../src/state/store
import ../../src/chain/[genesis, provider]
import ./[pvm_computed_storage_program, pvm_computed_chain, pvm_computed_state_publication,
  pvm_computed_assurances, pvm_assured_queue]

type AssuredOutcomeFixture* = object ## Test-owned handles retain genuine first execution and successor input authority, never substituted verdicts.
  prior*: AdvancedComputedChain
  first*: CompletedBlockAccumulation
  queue*: AssuredAccumulationQueue
  state*: StateStore
  view*: ChainView

proc assuredOutcomeFixture*(mode: ComputedStorageMode): AssuredOutcomeFixture =
  ## Author original programme/funding/gas before computation, publish it, then sign/admit actual successor assurances.
  assert mode != ComputedStorageMode.Disabled
  let source = chainFixture(storage = mode)
  let parent = source.chainFixtureParent(source.chainFixtureParameters)
  assert parent.error == GenesisError.None
  var state = forkStateStore(source.statePublicationParent).value
  var view = genesisView(parent).finalizeView(parent.value.blockHash).value
  let prior = advanceComputedChain(state, view, source).value
  let candidate = assuranceCandidate(prior)
  let assured = prepareComputedAssurances(prior, candidate, computedAssuranceConfig()).value
  let queue = prepareAssuredQueue(assured, assuredQueueConfig(assured)).value
  AssuredOutcomeFixture(prior: prior,
    first: source.computedCompositionSource.value.computedFinalizationSource.value.computedExecutionCompleted.value,
    queue: queue, state: state, view: view)
