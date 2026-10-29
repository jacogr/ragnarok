# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict guarded identity results/default owners with an actual selected parent/current successor control.
import std/[assertions, cmdline, syncio]
import ../support/[accumulation_current_chain_context, current_checkpoint_context,
    parent_logical_context, current_identity_context]
import ../../src/state/current/identities as current_identities
import ../../src/state/parent/logical as parent_logical
import ../../src/codec/report_owned
proc extract(value: CurrentIdentityResult[PreservedCurrentIdentities]) {.noinline.} =
  ## Defaults/refusals cannot expose a current preservation certificate.
  discard value.value
proc reason(value: CurrentIdentityResult[PreservedCurrentIdentities]) {.noinline.} =
  ## Only an actual missing/new identity result exposes its physical key.
  discard value.refusedIdentity
proc observe(mode: string, value: PreservedCurrentIdentities) {.noinline.} =
  ## Default owners cannot expose any original source, update or successful accounting.
  case mode
  of "parent": discard value.identityParent.value
  of "update": discard value.identityUpdate.value
  of "logical": discard value.identityLogical.value
  else: discard value.identityInfo.value
proc main() {.raises.} =
  ## Positive control derives both sources through real signed/current and exact full logical matching.
  case paramStr(1)
  of "default": extract(default(CurrentIdentityResult[PreservedCurrentIdentities]))
  of "reason": reason(default(CurrentIdentityResult[PreservedCurrentIdentities]))
  of "ok":
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let fixture = currentChainFixture(decodeOwnedReport(bytes, 2).value, completeState = true)
    let parent = selectedLogicalParent(fixture.currentChainSeeded).value
    let kept = preserveCurrentIdentities(parent, currentCheckpointPrepared(fixture), currentIdentityTestLimits)
    extract(kept)
    for mode in ["parent", "update", "logical", "info"]: observe(mode, kept.value)
    echo "state-current-identities-results: ok"
  else: observe(paramStr(1), default(PreservedCurrentIdentities))
try:
  main()
except:
  quit(2) # Positive setup failure is not a valid result/owner guard verdict.
