# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A default current slot has neither a queued update nor an acknowledged successful child.
import std/cmdline
import ../../src/app/current_handoff as app_current_handoff
var handoff = default(CurrentAccumulationHandoff)
let outcome = default(CurrentHandoffResult)
case paramStr(1)
of "pending": discard handoff.pendingUpdate # Only a pending slot retains a prepared update.
of "take": discard handoff.take # Only a finished slot retains an acknowledgment.
else: discard outcome.value # Default/refused results expose no captured child.
