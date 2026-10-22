# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict completed-origin owner/default source guards with an actual two-child current positive control.
import std/[assertions, cmdline, syncio]
import ../support/[current_repeated_logical_context, current_identity_context]
import ../../src/state/[current_identities, current_logical, accumulation_current_update]
import ../../src/codec/report_owned
proc extract(value: CurrentIdentityResult[PreservedCurrentIdentities]) {.noinline.} =
  ## No default completed source grants an authenticated preservation prefix.
  discard value.value
proc prior(value: PreservedCurrentIdentities) {.noinline.} =
  ## Default preserved owners expose no actual completed previous source.
  discard value.identityPriorCurrent.value
proc main() {.raises.} =
  ## Positive control executes and fully matches the first child, then genuinely prepares its next signed empty child.
  case paramStr(1)
  of "default": prior(default(PreservedCurrentIdentities))
  of "source": extract(preserveCurrentIdentities(default(CurrentLogicalState), default(
      PreparedCurrentChainUpdate), currentIdentityTestLimits))
  else:
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let fixture = repeatedLogicalFixture(decodeOwnedReport(bytes, 2).value)
    let kept = preserveCurrentIdentities(fixture.logical, fixture.next, currentIdentityTestLimits)
    extract(kept)
    prior(kept.value)
    assert kept.value.identityParent.error == CurrentIdentityError.WrongSource
    echo "state-current-identity-prior-results: ok"
try:
  main()
except:
  quit(2) # Genuine two-child preparation/full matching failures cannot become completed-origin guard evidence.
