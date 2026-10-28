# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit current completion policies match the signed two-core execution fixture and every current state phase.
import ../../src/state/accumulation_current_completion as state_accumulation_current_completion
import ../../src/state/accumulation_accounts as state_accumulation_accounts
import ../../src/state/accumulation_activity as state_accumulation_activity
import ../../src/state/accumulation_preimages as state_accumulation_preimages
import ../../src/state/accumulation_authorization as state_accumulation_authorization
import ../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../src/state/preimages as state_preimages
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/composite as codec_composite
import ./state_accumulation_current_statistics_context
import ./state_accumulation_current_finalization_context
import ./state_accumulation_ready_witnesses
import ./state_accumulation_recent_witnesses
import ./state_accumulation_activity_context
import ./state_accumulation_current_driver_context
proc currentCompositionLimits*(): CurrentAccumulationCompositionLimits =
  ## Local ceilings match existing phase witnesses without constructing any production authority.
  CurrentAccumulationCompositionLimits(statistics: currentStatisticsLimits(),
    accounts: AccumulationAccountConfig(services: ElementLimit(4), metadataBytes: ByteLimit(420)),
    finalization: currentFinalizationConfig(), ready: readyPolicy(), recent: recentPolicy(),
    validators: activityValidatorConfig(), activity: AccumulationActivityConfig(
      componentBytes: ByteLimit(1024), preimages: PreimageLimits(items: ElementLimit(3),
        perBlob: ByteLimit(3), totalBlobBytes: ByteLimit(4)), incoming: ElementLimit(2),
      available: ElementLimit(1), digests: ElementLimit(2), assurances: ElementLimit(5),
      provisions: ElementLimit(2), accumulation: ElementLimit(2), services: ElementLimit(2),
      activityBytes: ByteLimit(4096)),
    preimages: AccumulationPreimageLimits(items: ElementLimit(3), bytes: ByteLimit(4)),
    authorization: AccumulationAuthorizationLimits(guarantees: ElementLimit(2),
      inputHashes: ElementLimit(160), inputBytes: ByteLimit(5120), outputHashes: ElementLimit(16),
      outputBytes: ByteLimit(514)),
    consensus: AccumulationConsensusLimits(chapterBytes: ByteLimit(10000), totalBytes: ByteLimit(50000)))
proc currentCompletionLimits*(): CurrentAccumulationCompletionLimits =
  ## Initial/continuation execution remains independently capped from terminal state composition.
  CurrentAccumulationCompletionLimits(execution: currentSequenceDriverLimits(),
      composition: currentCompositionLimits())
