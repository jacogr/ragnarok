# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit current completion policies match the signed two-core execution fixture and every current state phase.
import ../../src/state/accumulation/current/completion as accumulation_current_completion
import ../../src/state/accumulation/[accounts as accumulation_accounts,
    activity as accumulation_activity, preimages as accumulation_preimages,
    authorization as accumulation_authorization, consensus as accumulation_consensus]
import ../../src/state/preimages
import ../../src/codec/[bounded, composite]
import ./[accumulation_current_statistics_context, accumulation_current_finalization_context,
  accumulation_ready_witnesses, accumulation_recent_witnesses, accumulation_activity_context,
  accumulation_current_driver_context]
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
