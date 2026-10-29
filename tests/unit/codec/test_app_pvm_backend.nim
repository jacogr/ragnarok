# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical backend CLI defaults, all explicit modes, strict refusals and dedicated-command extraction.
import std/[assertions, syncio, strutils]
import ../../../src/app/options
import ../../../src/app/cli/help as cli_help
import ../../../src/pvm/step

proc peer(): seq[string] =
  ## A complete named service command isolates backend parsing from missing transport arguments.
  @["server", "--net-port", "4000", "--net-cert", "node.pem", "--net-key", "node.key",
    "--net-peer-key", "-", "--net-alpn", "network"]

var parsedOptions = default(Options)
var diagnostic = ""
assert parseOptions(peer(), parsedOptions, diagnostic) and parsedOptions.pvmBackend == PvmBackend.Jit
assert ord(PvmBackend.Jit) == 0 and ord(PvmBackend.Interpreted) == 1 and
    ord(PvmBackend.PolkaInterpreted) == 2 and ord(PvmBackend.PolkaCompiled) == 3 and
        ord(PvmBackend.Compiled) == 4
for mode in [PvmBackend.Jit, PvmBackend.Compiled, PvmBackend.Interpreted,
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
var repeated = peer()
for value in ["--pvm-backend", "jit", "--pvm-backend", "interpreted"]: repeated.add(value)
assert not parseOptions(repeated, parsedOptions, diagnostic) and not parsedOptions.valid
var remaining: seq[string] = @[]
var selected = DefaultPvmBackend
assert not extractPvmBackend(@["fuzz", "--pvm-backend"], remaining, selected)
assert not extractPvmBackend(@["fuzz", "--pvm-backend", "jit", "--pvm-backend", "jit"], remaining, selected)
let help = commandHelp("server")
assert "--pvm-backend" in help and "compiled|interpreted" in help and "polkavm-compiled" in help
let unavailable = backendSummary(PvmBackend.Compiled)
assert "requested=compiled" in unavailable and "preparation=source-only" in unavailable and
    "availability=not-built" in unavailable and "revision=" notin unavailable
assert backendAvailability(PvmBackend.Compiled) == StepError.BackendNotBuilt
stdout.writeLine("PASS application PVM backend CLI")
