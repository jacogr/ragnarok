# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and actually refused marker derivations cannot expose a complete expected pair.
import std/[assertions, cmdline, syncio]
import ../../src/state/safrole_markers
import ../../src/codec/[state_safrole, header]
let outcome = if paramStr(1) == "default": default(SafroleMarkerResult) else:
  deriveSafroleMarkers([], [], StateTime(0), StateTime(1), default(StateEntropy), default(
      SafroleMarkerConfig)) # Actual invalid policy refusal.
assert paramStr(1) in ["default", "error"] # A selector failure cannot substitute for extraction protection.
assert outcome.error == (if paramStr(1) == "default": SafroleMarkerError.Uninitialized else: SafroleMarkerError.InvalidConfig)
echo epochMarkerInfo(outcome.value.epochMarker).value.present
