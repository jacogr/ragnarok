# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared application configuration, parsed once before any service opens a socket.
## Options owns copied positional arguments and explicit enable/configuration values. Failed parsing
## clears the output; private fields and read accessors prevent partial configuration from escaping.

import std/[strutils, assertions]

const
  Switches = ["--with-ui", "--with-rpc", "--with-telemetry"]
  Values = ["--telemetry", "--chain", "--rpc-port", "--ui-port", "--dev-ui-dir"]

type Options* = object ## Validated service controls; command handlers validate their positional shapes.
  parsed, telemetry, rpc, ui: bool
  positional: seq[string]
  endpoint, chain, directory: string
  rpcNumber, uiNumber: uint16

proc valid*(options: Options): bool =
  ## A failed/default configuration has no executable command or enabled services.
  options.parsed

proc argumentCount*(options: Options): int =
  ## Count only positional command arguments, excluding all trailing service controls.
  options.positional.len

proc argument*(options: Options, index: Positive): string =
  ## Preserve one-based CLI positions without consulting process-global arguments again.
  assert options.parsed and index <= options.positional.len
  options.positional[index - 1]

proc telemetryEnabled*(options: Options): bool =
  ## Endpoint configuration alone never enables the exporter.
  options.parsed and options.telemetry

proc rpcPort*(options: Options): uint16 =
  ## UI implies RPC; configuration alone leaves the listener disabled.
  if options.parsed and (options.rpc or options.ui): options.rpcNumber else: 0'u16

proc uiPort*(options: Options): uint16 =
  ## An enabled UI listener uses the validated configured port, defaulting to 8888.
  if options.parsed and options.ui: options.uiNumber else: 0'u16

proc telemetryEndpoint*(options: Options): string =
  ## Return the explicit collector address; no default collector is invented.
  options.endpoint

proc chainPath*(options: Options): string =
  ## RPC and telemetry share this one explicit startup source.
  options.chain

proc devUiDirectory*(options: Options): string =
  ## Empty selects embedded assets; an override replaces the entire asset source.
  options.directory

# Prove decimal width and range before narrowing a configured listener port.
proc portValue(text: string): uint16 =
  if text.len == 0 or text.len > 5: return 0
  var port = 0
  for digit in text: # Five decimal digits bound every intermediate arithmetic operation.
    if digit notin {'0'..'9'}: return 0
    port = port * 10 + ord(digit) - ord('0')
  if port notin 1..65535: return 0
  uint16(port)

proc parseOptions*(arguments: seq[string], options: var Options): bool =
  ## Parse unique trailing controls atomically; repeated invocations own independent configuration.
  options = default(Options)
  var candidate = Options(rpcNumber: 19800, uiNumber: 8888)
  var first = arguments.len
  for i in 0..<arguments.len: # Only reserved service controls begin the trailing option region.
    if arguments[i] in Switches or arguments[i] in Values:
      first = i
      break
  for i in 0..<first: candidate.positional.add(arguments[i]) # Copy caller arguments into this owner.
  var seen: seq[string] = @[]
  var i = first
  while i < arguments.len: # Reject unknown, duplicate, missing and option-valued pairs before use.
    let name = arguments[i]
    if name in seen: return false
    seen.add(name)
    if name in Switches:
      case name
      of "--with-telemetry": candidate.telemetry = true
      of "--with-rpc": candidate.rpc = true
      of "--with-ui": candidate.ui = true
      else: return false # Switch classification above makes this branch unreachable.
      inc i
    elif name in Values:
      if arguments.len - i < 2: return false
      let value = arguments[i + 1]
      if value.len == 0 or value.startsWith("--"): return false
      case name
      of "--telemetry": candidate.endpoint = value
      of "--chain": candidate.chain = value
      of "--dev-ui-dir": candidate.directory = value
      of "--rpc-port", "--ui-port":
        let port = portValue(value)
        if port == 0: return false # Never narrow a malformed or overflowing port.
        if name == "--rpc-port": candidate.rpcNumber = port
        else: candidate.uiNumber = port
      else: return false # All value-taking controls have an explicit assignment above.
      i += 2
    else: return false # Trailing controls never become protocol fixture modes.
  if candidate.telemetry and (candidate.endpoint.len == 0 or candidate.chain.len == 0): return false
  if candidate.chain.len > 0 and not (candidate.telemetry or candidate.rpc or
      candidate.ui): return false
  if candidate.ui and candidate.uiNumber == candidate.rpcNumber: return false
  if candidate.telemetry or candidate.rpc or candidate.ui:
    if candidate.positional.len == 0 or candidate.positional[0] notin ["server", "client", "mesh"]:
      return false # Socket services belong to network commands, never no-socket selftests.
  candidate.parsed = true
  options = candidate # Only a complete validated configuration replaces the cleared output.
  true
