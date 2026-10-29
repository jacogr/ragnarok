# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused account-source plans cannot reveal complete maps, copied metadata or producer outcomes.
import std/cmdline
import ../../src/state/accumulation/account/selection as accumulation_account_selection
import ../../src/state/accumulation/annulment as accumulation_annulment
let argument = paramStr(1)
let owner = default(PreparedAccumulationAccountSelection)
let refused = if argument == "default": default(AccumulationAccountSelectionResult[PreparedAccumulationAccountSelection])
  else: prepareAccumulationAccountSelection(default(PreparedAccumulationAnnulment), [], default(
      AccumulationAccountSelectionLimits))
case argument
of "skip": discard owner.selectedAccountSkipAt(AccumulationAccountSelectionIndex(
    0)).value # Default source grants no frame/input/skip payload.
of "info": discard owner.accountSelectionInfo.value # No fabricated empty subset.
of "source": discard owner.accountSelectionSource.value # No fake conflict certificate.
of "account": discard owner.selectedAccountAt(AccumulationAccountSelectionIndex(
    0)).value # No default presence/origin descriptor.
of "snapshot": discard owner.selectedAccountSnapshotAt(AccumulationAccountSelectionIndex(
    0)).value # No complete-map substitute.
of "metadata": discard owner.selectedAccountMetadataAt(AccumulationAccountSelectionIndex(
    0)).value # No fabricated zero metadata.
of "outcome": discard owner.selectedAccountOutcomeAt(AccumulationAccountSelectionIndex(
    0)).value # No fabricated mutating producer.
else: discard refused.value # Both default and invalid-source alternatives carry no successful owner.
