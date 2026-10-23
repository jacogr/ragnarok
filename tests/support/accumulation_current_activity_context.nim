# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current activity fixtures share exact signed inputs with legacy witnesses and retain real current completion.
import ./service_namespace_seed
import ../../src/codec/[bounded, header, composite, report_owned, state_authorization, state_trie]
import ../../src/state/[accumulation_current_activity, accumulation_current_validators,
  accumulation_current_recent, accumulation_current_ready, accumulation_current_finalization,
  accumulation_current_driver, accumulation_provisions]
import ./[accumulation_activity_context, accumulation_current_finalization_context,
  accumulation_current_round_context, accumulation_current_driver_context,
  accumulation_execution_context, accumulation_recent_witnesses, accumulation_ready_witnesses,
  pvm_accumulation_provision]
type CurrentActivityFixture* = object ## Full authored parent keys support independent selected-state reconstruction.
  source*: PreparedCurrentAccumulationValidators
  entries*: seq[StateEntry]
  older*: seq[OwnedHeader] ## Original genuine lookup headers support full candidate consumers.
proc currentActivityFixture*(base: OwnedReport, available = false, guarantees = 0, blobs = false,
    requested = true, missingLast = false, disordered = false, slot = 2'u32,
    hugeRefinement = false, executed = false, provided = false, parentPools: seq[AuthorizerRow] = @[],
    authorizationQueue: seq[byte] = @[], omitAuthorizationQueue = false,
    withDispute = false, withTicket = false, shiftPending = false,
    storeWrites = 1000'u64, completeState = false, serviceNamespaces: seq[ServiceNamespaceSeed] = @[]): CurrentActivityFixture =
  ## All signatures, current guests/selection, statistics, timestamps, queues and recent history remain genuine prerequisites.
  let fixture = executionFixture(base, activityOptions(available = available,
      guarantees = guarantees, blobs = blobs, requested = requested, missingLast = missingLast,
      disordered = disordered, slot = slot, hugeRefinement = hugeRefinement, executed = executed,
      provided = provided, parentPools = parentPools, authorizationQueue = authorizationQueue,
      omitAuthorizationQueue = omitAuthorizationQueue, withDispute = withDispute,
      withTicket = withTicket, shiftPending = shiftPending, storeWrites = storeWrites,
      completeState = completeState, serviceNamespaces = serviceNamespaces))
  var limits = currentSequenceDriverLimits()
  if provided:
    limits.initial.guests.provisions = provisionPolicy(items = 2, perBlob = 1, total = 2)
    limits.initial.provisions.values = PreimageLimits(items: ElementLimit(2), perBlob: ByteLimit(1),
        totalBlobBytes: ByteLimit(2))
    limits.initial.provisions.encodedBytes = ByteLimit(32)
    limits.execution.round = limits.initial # Real guest-provided values use the same finite capture policy on later entries.
  let completed = runCurrentBlockAccumulationSequence(fixture.round, currentRoundParameters(), limits).value
  let accounts = currentFinalizationAccounts(completed)
  let finalized = prepareCurrentAccumulationFinalization(accounts, currentFinalizationConfig()).value
  let ready = prepareCurrentAccumulationReady(finalized, readyPolicy()).value
  let recent = prepareCurrentAccumulationRecent(ready, recentPolicy()).value
  CurrentActivityFixture(source: prepareCurrentAccumulationValidators(recent,
      activityValidatorConfig()).value,
    entries: fixture.entries, older: fixture.older)
