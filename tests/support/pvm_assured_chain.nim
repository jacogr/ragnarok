# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine assured composition and reconstructed predecessor view reuse prepared publication without guest replay.

import std/assertions
import ../../src/state/[assured_composition, assured_execution, assured_queue, computed_assurances,
  computed_chain, computed_state_publication, computed_composition, accumulation_finalization, store]
import ../../src/chain/[genesis, provider]
import ./[pvm_assured_composition, pvm_computed_chain, pvm_computed_state_publication]

type AssuredChainSeed* = object ## Test-owned mutable handles retain the authentic published parent; no production certificate is fabricated.
  state*: StateStore
  view*: ChainView

proc assuredChainFixture*(votes = 7): ComposedAssuredState =
  ## Complete actual assured execution and composition before canonical publication is attempted.
  composeAssuredState(assuredCompositionFixture(votes), assuredCompositionConfig()).value
proc assuredChainSeed*(source: ComposedAssuredState): AssuredChainSeed =
  ## Re-adopt the closed predecessor's already prepared map, preserving physical owner and the real full header chain.
  let previous = source.assuredCompositionSource.value.assuredExecutionSource.value.assuredQueueSource.value.computedAssuranceSource.value
  let composed = previous.computedChainPublication.value.computedPublishedSource.value
  let parent = composed.chainFixtureParent(composed.chainFixtureParameters)
  assert parent.error == GenesisError.None
  var state = forkStateStore(composed.statePublicationParent).value
  var view = genesisView(parent).finalizeView(parent.value.blockHash).value
  let published = advanceComputedChain(state, view, composed)
  assert published.error == ComputedChainError.None
  assert sameStateSnapshot(state.snapshot.value, source.assuredCompositionFinal.value.finalAccumulationParent.value)
  assert view.bestBlock.value.slot == 2 and view.retainedCount == 2
  AssuredChainSeed(state: state, view: view)
