# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused recent history exposes no header/root/map prefix or inactive nested failure.
import std/cmdline
import ../../src/state/accumulation_current_recent as state_accumulation_current_recent
import ../../src/state/accumulation_recent as state_accumulation_recent
import ../../src/state/accumulation_current_ready as state_accumulation_current_ready
let owner = default(CurrentAccumulationRecentResult[PreparedCurrentAccumulationRecent])
let recent = default(PreparedCurrentAccumulationRecent)
let refused = prepareCurrentAccumulationRecent(default(PreparedCurrentAccumulationReady), default(
    AccumulationRecentConfig))
case paramStr(1)
of "refused": discard refused.value # No previous successful source after refusal.
of "source": discard recent.currentRecentSource.value # No fabricated predecessor.
of "history": discard recent.currentRecentHistory.value # No default initialized history.
of "root": discard recent.currentRecentRoot.value # No fake zero root.
of "state": discard recent.currentRecentState.value # No fake complete map.
of "entry": discard recent.currentRecentEntry.value # No initialized empty wire.
of "header-reason": discard refused.headerError # Require real selected header refusal.
of "codec-reason": discard refused.codecError # Require real selected codec refusal.
of "output-reason": discard refused.outputError # Require real selected output refusal.
of "history-reason": discard refused.historyError # Require real selected history refusal.
of "state-reason": discard refused.stateError # Require real selected store refusal.
else: discard owner.value # Default tagged result is uninitialized.
