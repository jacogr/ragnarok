# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused selected yield owners cannot reveal source, accounting, pair values or encoded log bytes.
import std/cmdline
import ../../src/state/accumulation/[annulled_outputs as accumulation_annulled_outputs,
    annulment as accumulation_annulment]
let argument = paramStr(1)
let owner = default(PreparedAnnulmentOutputs)
let refused = if argument == "default": default(AnnulmentOutputsResult[PreparedAnnulmentOutputs])
  else: prepareAnnulmentOutputs(default(PreparedAccumulationAnnulment), default(
      AnnulmentOutputLimits))
case argument
of "info": discard owner.annulmentOutputsInfo.value # No fabricated empty accounting.
of "source": discard owner.annulmentOutputsSource.value # No caller-authored conflict proof.
of "pair": discard owner.annulmentOutputAt(AnnulmentOutputIndex(0)).value # No fabricated all-zero pair.
of "entry": discard owner.annulmentOutputsEntry.value # No false empty canonical log.
else: discard refused.value # Default and invalid-source alternatives carry reasons alone.
