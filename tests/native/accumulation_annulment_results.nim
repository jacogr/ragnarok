# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused accpar certificates cannot expose owners, copied decisions or original/selected state payloads.
import std/cmdline
import ../../src/state/[accumulation_annulment, accumulation_inputs, store]
let argument = paramStr(1)
let owner = default(PreparedAccumulationAnnulment)
let refused = if argument == "default": default(AccumulationAnnulmentResult[PreparedAccumulationAnnulment])
  else: prepareAccumulationAnnulment(default(PreparedAccumulationInputs), default(
      StateStoreSnapshot), [],
    default(AccumulationAnnulmentLimits))
case argument
of "inputs": discard owner.annulmentInputs.value # Default source grants no frame/input/skip payload.
of "slot": discard owner.annulmentSlot.value # Default source grants no frame/input/skip payload.
of "info": discard owner.annulmentInfo.value # No fabricated empty accounting.
of "prior": discard owner.annulmentPrior.value # No default complete-map source.
of "decision": discard owner.annulmentDecisionAt(AccumulationAnnulmentIndex(
    0)).value # No forged conflict decision.
of "original": discard owner.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(
    0)).value # No genuine execution source.
of "selected-info": discard owner.annulmentSelectedInfoAt(AccumulationAnnulmentIndex(
    0)).value # No false gas/yield projection.
of "selected-state": discard owner.annulmentSelectedAccountsAt(AccumulationAnnulmentIndex(
    0)).value # No partial selected map.
of "modified": discard owner.annulmentSelectedModifiedCountAt(AccumulationAnnulmentIndex(
    0)).value # No fabricated empty set.
of "refused":
  discard prepareAccumulationAnnulment(default(PreparedAccumulationInputs), default(
      StateStoreSnapshot), [],
    default(AccumulationAnnulmentLimits)).value # A refused source never impersonates empty success.
else: discard refused.value # Default failed result carries no payload.
