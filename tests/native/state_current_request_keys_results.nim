# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict default cache/result guards with an actual nonempty signed/current key derivation control.
import std/[assertions, cmdline, syncio]
import ../support/current_request_keys_context
import ../../src/state/current/request_keys as current_request_keys
import ../../src/state/inventory
import ../../src/codec/report_owned
proc extract(value: CurrentRequestKeyResult[CurrentRequestKeys]) {.noinline.} =
  ## Defaults and failed captures expose no partial key cache.
  discard value.value
proc reason(value: CurrentRequestKeyResult[CurrentRequestKeys]) {.noinline.} =
  ## Only actual failed key derivation grants its typed original request reason.
  discard value.requestError
proc observe(mode: string, value: CurrentRequestKeys) {.noinline.} =
  ## No default cache owner grants a source, info or physical key.
  case mode
  of "source": discard value.requestKeysSource.value
  of "key": discard value.currentRequestKeyAt(InventoryServiceIndex(0), InventoryRequestIndex(0)).value
  else: discard value.requestKeysInfo.value
proc main() {.raises.} =
  ## Positive control builds full actual original/current nonempty state and bounded cached key derivation.
  case paramStr(1)
  of "default": extract(default(CurrentRequestKeyResult[CurrentRequestKeys]))
  of "reason": reason(default(CurrentRequestKeyResult[CurrentRequestKeys]))
  of "ok":
    let raw = readFile(paramStr(2))
    var bytes = newSeq[byte](raw.len)
    for i in 0..<raw.len: bytes[i] = byte(raw[i])
    let outcome = captureCurrentRequestKeys(namespacePreservation(decodeOwnedReport(bytes,
        2).value), currentRequestKeyTestLimits)
    extract(outcome)
    for mode in ["source", "key", "info"]: observe(mode, outcome.value)
    echo "state-current-request-keys-results: ok"
  else: observe(paramStr(1), default(CurrentRequestKeys))
try:
  main()
except:
  quit(2) # Original signed/current source failure cannot stand in for guard diagnostics.
