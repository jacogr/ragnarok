# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and actually refused marker derivations cannot expose a complete expected pair.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[assertions, cmdline, syncio]
import ../../src/state/safrole/markers as safrole_markers
import ../../src/codec/state/safrole as state_safrole
import ../../src/codec/header
let outcome = if paramStr(1) == "default": default(SafroleMarkerResult) else:
  deriveSafroleMarkers([], [], StateTime(0), StateTime(1), default(StateEntropy), default(
      SafroleMarkerConfig)) # Actual invalid policy refusal.
assert paramStr(1) in ["default", "error"] # A selector failure cannot substitute for extraction protection.
assert outcome.error == (if paramStr(1) == "default": SafroleMarkerError.Uninitialized else: SafroleMarkerError.InvalidConfig)
echo epochMarkerInfo(outcome.value.epochMarker).value.present
