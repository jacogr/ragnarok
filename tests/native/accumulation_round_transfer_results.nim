# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and refused completed-round transfer plans never expose source provenance, copied gas or a collection.

import std/cmdline
import ../../src/state/[accumulation_round_transfers, accumulation_execution,
    accumulation_transfers]
let argument = paramStr(1)
let owner = default(PreparedRoundAccumulationTransfers)
let result = if argument == "default": default(AccumulationRoundTransferResult[PreparedRoundAccumulationTransfers])
  else: prepareRoundAccumulationTransfers(default(CompletedBlockAccumulation), default(
      AccumulationTransferCollectionLimits))
case argument
of "info": discard owner.roundTransferInfo.value # No fabricated outgoing gas or counts.
of "source": discard owner.roundTransferSource.value # No substitute completed admitted round.
of "collection": discard owner.roundTransferCollection.value # No synthesized empty transfer sequence.
else: discard result.value # Both default and explicit invalid-source results require selected success.
