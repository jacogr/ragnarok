# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused creation union alternatives cannot reveal metadata, maps, outcomes or identities.
import std/cmdline
import ../../src/state/[accumulation_creation_union, accumulation_annulment]
let argument = paramStr(1)
let owner = default(PreparedAccumulationCreationUnion)
let ordinal = AccumulationCreationIndex(0)
let refused = if argument == "default": default(AccumulationCreationResult[PreparedAccumulationCreationUnion])
  else: prepareAccumulationCreationUnion(default(PreparedAccumulationAnnulment), default(
      AccumulationCreationLimits))
case argument
of "info": discard owner.creationUnionInfo.value # No false empty count.
of "source": discard owner.creationUnionSource.value # No false conflict source.
of "entry": discard owner.createdAccountAt(ordinal).value # No false child identity.
of "metadata": discard owner.createdAccountMetadataAt(ordinal).value # No false account values.
of "snapshot": discard owner.createdAccountSnapshotAt(ordinal).value # No false final map.
of "outcome": discard owner.createdAccountOutcomeAt(ordinal).value # No fabricated execution.
else: discard refused.value # A refusal carries its reason alone.
