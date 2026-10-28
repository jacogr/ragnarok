# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine computed successors with original privilege/gas authority and bounded initial-round policies.

import ./pvm_computed_storage_program
import ../../src/state/computed_publication as state_computed_publication
import ../../src/state/computed_admission as state_computed_admission
import ../../src/state/computed_inclusion as state_computed_inclusion
import ../../src/state/computed_batch as state_computed_batch
import ../../src/state/computed_envelope as state_computed_envelope
import ../../src/state/computed_credentials as state_computed_credentials
import ../../src/state/computed_guarantors as state_computed_guarantors
import ../../src/state/computed_roster as state_computed_roster
import ../../src/state/computed_transition as state_computed_transition
import ../../src/state/computed_profile as state_computed_profile
import ../../src/state/computed_round as state_computed_round
import ../../src/chain/parameters as chain_parameters
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/assurances as codec_assurances
import ../../src/codec/work_digest as codec_work_digest
import ./pvm_computed_publication
import ./state_accumulation_execution_context

proc roundFixture*(withReady = true, withRound = true,
    withExecution = false, invalidEntry = false, withComposition = false,
        withChain = false, storage = ComputedStorageMode.Disabled): ComputedReportSuccessor =
  ## Complete all actual computation/signing/admission before preparing the immutable C(10) successor.
  prepareComputedPublication(publicationFixture(withReady = withReady, withRound = withRound,
      withExecution = withExecution, invalidEntry = invalidEntry,
      withComposition = withComposition, withChain = withChain, storage = storage), ByteLimit(100000)).value
proc computedRoundConfig*(source: ComputedReportSuccessor): ComputedRoundConfig =
  ## Keep semantic gas exactly original while independently bounding queue, privilege and invocation-input work.
  let batch = source.computedSuccessorSource.value.computedAdmissionSource.value.computedInclusionSource.value
  let first = batch.computedBatchSourceAt(ComputedBatchIndex(0)).value
  let parameters = first.computedEnvelopeSource.value.computedCredentialSource.value.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileContext.value.parameters
  result = ComputedRoundConfig(queue: executionQueueConfig(), round: executionRoundConfig())
  result.queue.queues.cores = CoreCount(3)
  result.round.privileges.cores = CoreCount(3)
  result.round.reportGas = Gas(parameters.get(maxAccumulateGas))
  result.round.blockGas = Gas(parameters.get(blockGasLimit))
