# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused output owners cannot expose pairs, wire, source or roots.
import std/cmdline
import ../../src/codec/state/outputs as state_outputs
import ../../src/state/accumulation/current/[outputs as accumulation_current_outputs,
    driver as accumulation_current_driver]
let owner = default(CurrentAccumulationOutputsResult[PreparedCurrentAccumulationOutputs])
let outputs = default(PreparedCurrentAccumulationOutputs)
let refused = prepareCurrentAccumulationOutputs(default(CompletedCurrentAccumulationSequence),
    default(CurrentAccumulationOutputLimits))
case paramStr(1)
of "refused": discard refused.value # Only complete success permits owner extraction.
of "info": discard outputs.currentOutputsInfo.value # Defaults have no complete observations.
of "source": discard outputs.currentOutputsSource.value # Defaults have no terminal source.
of "pair": discard outputs.currentOutputAt(OutputLogIndex(0)).value # No fabricated zero pair.
of "entry": discard outputs.currentOutputsEntry.value # No fake initialized empty encoding.
of "root": discard outputs.currentOutputsRoot.value # No fake zero accumulation root.
of "history": discard refused.historyFailure # Require a real selected history failure.
else: discard owner.value # Default tagged result remains uninitialized.
