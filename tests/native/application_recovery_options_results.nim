# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque option helpers require complete active recovery with real successful parser controls.
import std/[assertions, cmdline]
import ../../src/app/options
proc inspect(options: Options, field: string) =
  ## Each accessor is checked independently at runtime.
  case field
  of "path": discard options.recoveryPath # Checkpoint selection requires active recovery.
  of "trust": discard options.recoveryTrustPath # Independent identity selection has the same gate.
  of "header": discard options.recoveryHeaderPath # Sealed bytes cannot be selected by default options.
  else: discard options.recoveryByteLimit # No inactive resource budget can authorize recovery.
proc main() =
  ## Default and valid-but-disabled options must fail the same helpers used by complete active parsing.
  var options = default(Options)
  if paramStr(1) == "positive":
    assert parseCanonicalOptions(@["server", "--with-state", "--chain", "chain.json",
      "--state-writes", "0",
      "--state-write-bytes", "0",
      "--state-checkpoint", "state.bin", "--state-trust", "trust.bin", "--state-header",
      "header.bin", "--state-checkpoint-bytes", "1000"], options)
    for field in ["path", "trust", "header", "bytes"]:
      inspect(options, field) # Every exact helper succeeds for a genuine active parser result.
  else:
    if paramStr(1) == "disabled":
      assert parseCanonicalOptions(@["server"], options) # Parsed status alone cannot authorize external recovery.
    inspect(options, paramStr(2))
main() # Runtime assertions remain distinct from compiler rejection.
