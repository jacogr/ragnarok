# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Guard current-global payloads and exact failed-global reasons with an actual prepared producer success control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_current_checkpoint_context
import ../support/state_accumulation_current_chain_context
import ../../src/state/current_globals as state_current_globals
import ../../src/state/current_profile as state_current_profile
import ../../src/state/global_snapshot as state_global_snapshot
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/state_composition as codec_state_composition
proc extract(outcome: CurrentGlobalsResult[CurrentGlobalSerialization]) {.noinline.} =
  ## No failed/default global qualification grants its owner.
  discard outcome.value
proc reason(outcome: CurrentGlobalsResult[CurrentGlobalSerialization]) {.noinline.} =
  ## Unrelated alternatives invent no failed global cause.
  discard outcome.globalFailure
proc globals(source: CurrentGlobalSerialization) {.noinline.} =
  ## Default owners grant no all-chapter certificate.
  discard source.qualifiedGlobals.value
proc profile(source: CurrentGlobalSerialization) {.noinline.} =
  ## Default owners grant no producer/profile projection.
  discard source.qualifiedCurrentProfile.value
proc main() {.raises.} =
  ## Fixture I/O belongs to the genuine positive control, outside intended negative verdicts.
  let limits = GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(10000),
      maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))
  case paramStr(1)
  of "default": extract(default(CurrentGlobalsResult[CurrentGlobalSerialization]))
  of "invalid": extract(qualifyCurrentGlobals(default(DerivedCurrentProfile), limits))
  of "reason": reason(default(CurrentGlobalsResult[CurrentGlobalSerialization]))
  of "globals": globals(default(CurrentGlobalSerialization))
  of "profile": profile(default(CurrentGlobalSerialization))
  of "ok":
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let source = currentCheckpointPrepared(currentChainFixture(decodeOwnedReport(bytes, 2).value,
        available = true))
    let projection = captureCurrentProfile(source, CurrentProfileLimits(validators: ElementLimit(
        1024), bytes: ByteLimit(65536))).value
    let result = qualifyCurrentGlobals(projection, limits)
    extract(result)
    assert result.value.qualifiedGlobals.value.globalByteLength.value > 0
    echo "state-current-globals-results: ok"
  else: quit(2) # Unknown selectors cannot qualify the intended guard.
try:
  main()
except:
  quit(2) # Setup failure cannot satisfy guarded extraction evidence.
