# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime extraction guards retain selected-success and genuine failed-file/header controls.
import std/[assertions, cmdline, syncio]
import std/posix/posix
import ../../src/app/ancestor/inputs as ancestor_inputs
import ../../src/codec/[bounded, header]
proc extract(outcome: AncestorInputResult) =
  ## Runtime inputs keep this a real extraction precondition check.
  discard outcome.headers
proc fileReason(outcome: AncestorInputResult) =
  ## Only an actual file refusal carries this reason.
  discard outcome.fileError
proc headerReason(outcome: AncestorInputResult) =
  ## Only an actual decoder refusal carries this reason.
  discard outcome.headerError
proc main() {.raises.} =
  ## Defaults/refusals and positive controls pass through the same runtime helpers.
  let config = fullHeaderConfig(ByteLimit(1024))
  case paramStr(1)
  of "default": extract(default(AncestorInputResult)) # Defaults expose no headers.
  of "refused": extract(loadAncestorInputs([""], config, ElementLimit(0), ByteLimit(
      0))) # Count refusal has no prefix.
  of "file": fileReason(default(AncestorInputResult)) # A default has no native cause.
  of "header": headerReason(default(AncestorInputResult)) # A default has no decoder cause.
  else:
    extract(loadAncestorInputs([], config, ElementLimit(0), ByteLimit(0)))
    fileReason(loadAncestorInputs([""], config, ElementLimit(1), ByteLimit(1024)))
    writeFile("ancestor-guard-empty", "")
    defer: discard posix.unlink("ancestor-guard-empty") # Positive controls retire their own regular input.
    headerReason(loadAncestorInputs(["ancestor-guard-empty"], config, ElementLimit(1), ByteLimit(1024)))
try:
  main() # Unexpected IO exceptions are not successful assertion witnesses.
except:
  quit(2)
