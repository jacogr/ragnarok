# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Publish one fully composed computed state against its exact original parent and retain the authentic receipt.

import ../composition as computed_composition
import "../../accumulation/block/publication" as accumulation_block_publication
import ../../store

type
  ComputedStatePublicationError* {.pure.} = enum ## Only selected publication failure carries a complete precise child refusal.
    Uninitialized, None, InvalidSource, PublicationFailure
  ComputedStatePublicationData = ref object ## Immutable acyclic receipt retains original work and the exact adopted complete map.
    source: ComposedComputedState
    snapshot: StateStoreSnapshot
  PublishedComputedState* = object ## Successful publication is not chain-view advancement or complete block/finality validation.
    data: nil ComputedStatePublicationData
  ComputedStatePublicationResult*[T] = object ## Defaults and refusals expose no successful publication receipt.
    case status: ComputedStatePublicationError
    of None:
      completed: T
    of PublicationFailure:
      publicationReason: AccumulationPublicationResult
    else:
      discard # Ordinary reasons retain no state or computed work.

func error*[T](outcome: ComputedStatePublicationResult[T]): ComputedStatePublicationError =
  ## Inspect reason without writable discriminator access.
  outcome.status

func value*[T](outcome: ComputedStatePublicationResult[T]): T
    {.requires: outcome.status == ComputedStatePublicationError.None.} =
  ## Extract only a real successful receipt under optimized contracts.
  outcome.completed

func publicationFailure*[T](outcome: ComputedStatePublicationResult[
    T]): AccumulationPublicationResult
    {.requires: outcome.status == ComputedStatePublicationError.PublicationFailure.} =
  ## Preserve the exact selected publication phase and guarded nested store cause.
  outcome.publicationReason

proc computedPublishedSource*(published: PublishedComputedState): ComputedStatePublicationResult[
    ComposedComputedState] =
  ## Share original computed composition authority after caller preparation handles retire.
  let data = published.data
  if data == nil: return ComputedStatePublicationResult[ComposedComputedState](
      status: ComputedStatePublicationError.Uninitialized)
  ComputedStatePublicationResult[ComposedComputedState](status: ComputedStatePublicationError.None,
      completed: data.source)

proc computedPublishedSnapshot*(published: PublishedComputedState): ComputedStatePublicationResult[
    StateStoreSnapshot] =
  ## Share the exact adopted immutable state independently of later target updates.
  let data = published.data
  if data == nil: return ComputedStatePublicationResult[StateStoreSnapshot](
      status: ComputedStatePublicationError.Uninitialized)
  ComputedStatePublicationResult[StateStoreSnapshot](status: ComputedStatePublicationError.None,
      completed: data.snapshot)

proc publishComputedState*(state: var StateStore, source: ComposedComputedState): ComputedStatePublicationResult[
    PublishedComputedState] =
  ## Delegate exact-parent adoption without rehashing, recomposition, guest execution or caller-supplied replacement maps.
  let selected = source.computedCompositionPlan
  if selected.error != ComputedCompositionError.None:
    return ComputedStatePublicationResult[PublishedComputedState](
        status: ComputedStatePublicationError.InvalidSource)
  let adopted = publishAccumulationState(state, selected.value)
  if adopted.error != AccumulationPublicationError.None:
    return ComputedStatePublicationResult[PublishedComputedState](
        status: ComputedStatePublicationError.PublicationFailure, publicationReason: adopted)
  ComputedStatePublicationResult[PublishedComputedState](status: ComputedStatePublicationError.None,
      completed: PublishedComputedState(data: ComputedStatePublicationData(source: source,
      snapshot: adopted.value)))
