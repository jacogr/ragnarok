# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Inactive account phase owners and reasons remain guarded at runtime.
import std/cmdline
import ../../src/state/accumulation_account_stage as state_accumulation_account_stage
import ../../src/state/accumulation_block_guests as state_accumulation_block_guests
let owner = default(AccumulationAccountStageResult[PreparedAccumulationAccountStage])
let refused = prepareAccumulationAccountStage(default(BlockAccumulationGuests), default(
    AccumulationAccountStageLimits))
let stage = default(PreparedAccumulationAccountStage)
case paramStr(1)
of "refused": discard refused.value # Only successful selected alternatives authorize this extraction.
of "selection": discard owner.selectionFailure # Only successful selected alternatives authorize this extraction.
of "creation": discard owner.creationFailure # Only successful selected alternatives authorize this extraction.
of "write": discard owner.writeFailure # Only successful selected alternatives authorize this extraction.
of "store": discard owner.storeFailure # Only successful selected alternatives authorize this extraction.
of "info": discard stage.accountStageInfo.value # Only successful selected alternatives authorize this extraction.
of "guests": discard stage.accountStageGuests.value # Only successful selected alternatives authorize this extraction.
of "selected": discard stage.accountStageSelection.value # Only successful selected alternatives authorize this extraction.
of "created": discard stage.accountStageCreation.value # Only successful selected alternatives authorize this extraction.
of "writes": discard stage.accountStageWrites.value # Only successful selected alternatives authorize this extraction.
of "snapshot": discard stage.accountStageSnapshot.value # Only successful selected alternatives authorize this extraction.
else: discard owner.value # No default complete account phase.
