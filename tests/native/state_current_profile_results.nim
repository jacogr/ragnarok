# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict current-profile payload/reason guards retain a genuinely prepared current child as positive control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_current_checkpoint_context
import ../support/state_accumulation_current_chain_context
import ../../src/state/current_profile as state_current_profile
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/state_composition as codec_state_composition
proc extract(outcome: CurrentProfileResult[DerivedCurrentProfile]) {.noinline.} =
  ## Default/refused projection grants no source-bound profile.
  discard outcome.value
proc reason(outcome: CurrentProfileResult[DerivedCurrentProfile]) {.noinline.} =
  ## Unrelated alternatives invent no C9 decoder refusal.
  discard outcome.previousError
proc profile(source: DerivedCurrentProfile) {.noinline.} =
  ## A default projection grants no cardinalities.
  discard source.derivedStateProfile.value
proc parameters(source: DerivedCurrentProfile) {.noinline.} =
  ## A default projection grants no full execution tuple.
  discard source.derivedParameters.value
proc origin(source: DerivedCurrentProfile) {.noinline.} =
  ## A default projection grants no producer owner.
  discard source.derivedUpdate.value
proc main() {.raises.} =
  ## Trusted fixture I/O is bounded by the caller's signed native control setup.
  case paramStr(1)
  of "default": extract(default(CurrentProfileResult[DerivedCurrentProfile]))
  of "invalid": extract(captureCurrentProfile(default(PreparedCurrentChainUpdate),
      CurrentProfileLimits()))
  of "reason": reason(default(CurrentProfileResult[DerivedCurrentProfile]))
  of "profile": profile(default(DerivedCurrentProfile))
  of "parameters": parameters(default(DerivedCurrentProfile))
  of "origin": origin(default(DerivedCurrentProfile))
  of "ok":
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let source = currentCheckpointPrepared(currentChainFixture(decodeOwnedReport(bytes, 2).value,
        available = true))
    let captured = captureCurrentProfile(source, CurrentProfileLimits(validators: ElementLimit(6),
        bytes: ByteLimit(2017)))
    extract(captured)
    assert captured.value.derivedStateProfile.value.valid
    echo "state-current-profile-results: ok"
  else: quit(2) # Unknown selectors cannot satisfy guarded evidence.
try:
  main()
except:
  quit(2) # Fixture errors are not intended payload/reason refusals.
