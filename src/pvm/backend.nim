# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Closed engine identities bind prepared owners and completed observations; no CLI policy lives here.
type PvmBackend* {.pure.} = enum
  ## The independent engine and explicit upstream engines never silently substitute for one another.
  Jit = "jit", Interpreted = "interpreted", PolkaInterpreted = "polkavm-interpreted",
      PolkaCompiled = "polkavm-compiled"

const PolkaVmRevision* = "69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa"
  ## Loaded optional bridges must match the pristine pinned public runtime.

const DefaultPvmBackend* = PvmBackend.Jit
  ## The independent JIT policy preserves checked same-engine fallback whenever native work is unavailable.

proc parsePvmBackend*(name: string, selected: var PvmBackend): bool =
  ## Accept only the canonical explicit engine/policy spellings.
  for candidate in [PvmBackend.Jit, PvmBackend.Interpreted, PvmBackend.PolkaInterpreted,
      PvmBackend.PolkaCompiled]:
    if $candidate == name:
      selected = candidate
      return true
  false

proc extractPvmBackend*(arguments: seq[string], remaining: var seq[string],
    selected: var PvmBackend): bool =
  ## Dedicated command grammars consume the same unique option before validating their own controls.
  remaining = @[]
  selected = DefaultPvmBackend
  var seen = false
  var index = 0
  while index < arguments.len:
    if arguments[index] == "--pvm-backend":
      if seen or arguments.len-index < 2: return false
      if not parsePvmBackend(arguments[index+1], selected): return false
      seen = true
      index+=2
    else:
      remaining.add(arguments[index])
      inc index
  true

proc backendSummary*(selected: PvmBackend): string =
  ## Startup observes requested policy and supported architecture without promising native execution of every opcode.
  result = "PVM_BACKEND requested=" & $selected
  if selected == PvmBackend.Jit:
    when defined(pvmX86Jit) and defined(amd64) and defined(linux):
      result &= " native-platform=x86-64 checked-fallback=enabled"
    elif defined(pvmArm64Jit) and not defined(pvmX86Jit) and defined(arm64) and (defined(linux) or
        defined(macosx)):
      result &= " native-platform=arm64 checked-fallback=enabled"
    else:
      result &= " native-platform=unavailable actual=interpreted checked-fallback=enabled"
  elif selected == PvmBackend.Interpreted:
    result &= " actual=interpreted native=disabled"
  else:
    result &= " revision=" & PolkaVmRevision & " fallback=disabled"
