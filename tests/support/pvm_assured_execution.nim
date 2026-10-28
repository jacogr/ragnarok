# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual assurance-fed queues and independently bounded original-parameter execution policies.

import ../../src/state/assured_execution as state_assured_execution
import ../../src/state/assured_queue as state_assured_queue
import ../../src/chain/parameters as chain_parameters
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/assurances as codec_assurances
import ../../src/codec/work_digest as codec_work_digest
import ./pvm_assured_queue
import ./pvm_computed_execution
import ./state_accumulation_execution_context

proc assuredExecutionFixture*(votes = 7): AssuredAccumulationQueue =
  ## Derive the real next queue from authenticated availability, with no injected ready item.
  let source = assuredQueueFixture(votes)
  prepareAssuredQueue(source, assuredQueueConfig(source)).value
proc assuredExecutionConfig*(source: AssuredAccumulationQueue): AssuredExecutionConfig =
  ## Match original semantic gas and actual three-core frame; bound two inputs and one supported storage key independently.
  let params = source.assuredQueueParameters.value
  result = AssuredExecutionConfig(round: executionRoundConfig(), runner: computedExecutionLimits())
  result.round.privileges.cores = CoreCount(3)
  result.round.reportGas = Gas(params.get(maxAccumulateGas))
  result.round.blockGas = Gas(params.get(blockGasLimit))
  result.runner.fetch.items = ElementLimit(2)
  result.runner.accountWriteKeys = ElementLimit(1)
  result.runner.completion.batch.selfWrites = ElementLimit(1)
  result.runner.completion.batch.selfValueBytes = ByteLimit(3)
