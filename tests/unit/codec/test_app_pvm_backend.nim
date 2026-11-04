# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical backend CLI defaults, all explicit modes, strict refusals and dedicated-command extraction.
import std/[assertions, syncio, strutils]
import ../../../src/app/options
import ../../../src/app/cli/commands
import ../../../src/app/cli/help as cli_help

proc peer(): seq[string] =
  ## A complete named service command isolates backend parsing from missing transport arguments.
  @["server", "--net-port", "4000", "--net-cert", "node.pem", "--net-key", "node.key",
    "--net-peer-key", "-", "--net-alpn", "network"]

var parsedOptions = default(Options)
var diagnostic = ""
assert parseOptions(peer(), parsedOptions, diagnostic) and parsedOptions.pvmBackend == PvmBackend.Jit
assert ord(PvmBackend.Jit) == 0 and ord(PvmBackend.Interpreted) == 1 and
    ord(PvmBackend.PolkaInterpreted) == 2 and ord(PvmBackend.PolkaCompiled) == 3
for mode in [PvmBackend.Jit, PvmBackend.Interpreted,
    PvmBackend.PolkaInterpreted, PvmBackend.PolkaCompiled]:
  var input = peer()
  input.add("--pvm-backend=" & $mode)
  assert parseOptions(input, parsedOptions, diagnostic), diagnostic
  assert parsedOptions.pvmBackend == mode
  var remaining: seq[string] = @[]
  var selected = DefaultPvmBackend
  assert extractPvmBackend(@["fuzz", "--pvm-backend", $mode, "--fuzz-path", "owned"], remaining, selected)
  assert selected == mode and remaining == @["fuzz", "--fuzz-path", "owned"]
for value in ["", "native", "ragnarok", "polkavm-native", "JIT", "auto", "Compiled", "compiled "]:
  var input = peer()
  input.add("--pvm-backend")
  input.add(value)
  assert not parseOptions(input, parsedOptions, diagnostic)
  assert not parsedOptions.valid
for backendOption in [@["--pvm-backend", "compiled"], @["--pvm-backend=compiled"]]:
  # Removed policy spellings must refuse before either normal or dedicated command execution.
  var input = peer()
  var dedicated = @["fuzz"]
  for argument in backendOption:
    # Both command paths consume the same owned split/equals process arguments.
    input.add(argument)
    dedicated.add(argument)
  assert not parseOptions(input, parsedOptions, diagnostic) and not parsedOptions.valid
  var normalized: seq[string] = @[]
  var remaining: seq[string] = @[]
  var selected = DefaultPvmBackend
  # A dedicated command may refuse the flag during normalization or reject its removed mode afterward.
  assert not (normalizeCommand(dedicated, normalized, diagnostic) and
      extractPvmBackend(normalized, remaining, selected))
var repeated = peer()
for value in ["--pvm-backend", "jit", "--pvm-backend", "interpreted"]: repeated.add(value)
assert not parseOptions(repeated, parsedOptions, diagnostic) and not parsedOptions.valid
var remaining: seq[string] = @[]
var selected = DefaultPvmBackend
assert not extractPvmBackend(@["fuzz", "--pvm-backend"], remaining, selected)
assert not extractPvmBackend(@["fuzz", "--pvm-backend", "compiled"], remaining, selected)
assert not extractPvmBackend(@["fuzz", "--pvm-backend", "jit", "--pvm-backend", "jit"], remaining, selected)
let help = commandHelp("server")
assert "--pvm-backend" in help
for mode in [PvmBackend.Jit, PvmBackend.Interpreted, PvmBackend.PolkaInterpreted,
    PvmBackend.PolkaCompiled]:
  # Help advertises each supported mode without constraining presentation order.
  assert $mode in help
stdout.writeLine("PASS application PVM backend CLI")
