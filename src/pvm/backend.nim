# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit guest engine identity, independent of protocol gas and private Ragnarök policies.
## Parsing never selects an engine implicitly or consults process environment variables.

type PvmBackend* {.pure.} = enum ## The default retains the independent implementation.
  Ragnarok = "ragnarok"
  PolkaVmInterpreted = "polkavm-interpreted"
  PolkaVmNative = "polkavm-native"

const PolkaVmRevision* = "69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa" ## Pristine upstream public API pin.

proc parsePvmBackend*(text: string, selected: var PvmBackend): bool =
  ## Accept exactly the public spellings; refusal clears any earlier selected value.
  selected = PvmBackend.Ragnarok
  case text
  of "ragnarok": return true # Explicit default is useful in deployment configuration.
  of "polkavm-interpreted": selected = PvmBackend.PolkaVmInterpreted
  of "polkavm-native": selected = PvmBackend.PolkaVmNative
  else: return false # Unknown names cannot become environment-dependent defaults.
  true

proc extractPvmBackend*(arguments: seq[string], remaining: var seq[string],
    selected: var PvmBackend): bool =
  ## Dedicated command grammars share one explicit engine flag without reading environment defaults.
  remaining = @[]
  selected = PvmBackend.Ragnarok
  var seen = false
  var index = 0
  while index < arguments.len:
    if arguments[index] == "--pvm-backend":
      if seen or arguments.len-index < 2: return false
      if not parsePvmBackend(arguments[index+1], selected): return false
      seen = true
      index += 2 # Consuming the exact pair preserves every command-owned positional argument.
    else:
      remaining.add(arguments[index])
      inc index
  true
