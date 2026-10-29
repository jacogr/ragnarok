# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine computed successors with original privilege/gas authority and bounded initial-round policies.

import ./pvm_computed_storage_program
import ../../src/state/computed/[publication as computed_publication,
    admission as computed_admission, inclusion as computed_inclusion, batch as computed_batch,
    envelope as computed_envelope, credentials as computed_credentials,
    guarantors as computed_guarantors, roster as computed_roster, transition as computed_transition,
    profile as computed_profile, round as computed_round]
import ../../src/chain/parameters
import ../../src/codec/[bounded, assurances]
import ../../src/codec/work/digest as work_digest
import ./[pvm_computed_publication, accumulation_execution_context]

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
