# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical backend CLI defaults, all explicit modes, strict refusals and dedicated-command extraction.
import std/assertions
import std/syncio
import std/strutils
import ../../../src/app/options as app_options
import ../../../src/app/cli_help as app_cli_help

proc peer(): seq[string] =
  ## A complete named service command isolates backend parsing from missing transport arguments.
  @["server", "--net-port", "4000", "--net-cert", "node.pem", "--net-key", "node.key",
    "--net-peer-key", "-", "--net-alpn", "network"]

var parsedOptions = default(Options)
var diagnostic = ""
assert parseOptions(peer(), parsedOptions, diagnostic) and parsedOptions.pvmBackend == PvmBackend.Jit
for mode in [PvmBackend.Jit, PvmBackend.Interpreted, PvmBackend.PolkaInterpreted,
    PvmBackend.PolkaCompiled]:
  var input = peer()
  input.add("--pvm-backend=" & $mode)
  assert parseOptions(input, parsedOptions, diagnostic), diagnostic
  assert parsedOptions.pvmBackend == mode
  var remaining: seq[string] = @[]
  var selected = DefaultPvmBackend
  assert extractPvmBackend(@["fuzz", "--pvm-backend", $mode, "--fuzz-path", "owned"], remaining, selected)
  assert selected == mode and remaining == @["fuzz", "--fuzz-path", "owned"]
for value in ["", "native", "ragnarok", "polkavm-native", "JIT", "auto"]:
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
assert "--pvm-backend" in help and "polkavm-compiled" in help
stdout.writeLine("PASS application PVM backend CLI")
