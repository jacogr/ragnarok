# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Normalize named command inputs into the existing private command-handler representation.
## Positional command values and unknown/duplicate flags are refused before startup.

import std/[strutils, os]
import ./cli_catalog

proc unsignedValue*(text: string, value: var uint64): bool =
  ## Parse one unsigned decimal with checked multiply/add; zero is data, never a failure sentinel.
  value = 0
  if text.len == 0 or text.len > 20: return false
  for character in text:
    if character notin {'0'..'9'}: return false # Reject signs, whitespace and non-ASCII numerals.
    let digit = uint64(ord(character)-ord('0'))
    if value > (high(uint64)-digit) div 10: return false # Prove arithmetic before multiplication.
    value = value*10+digit
  true

proc boundedNumber(text: string, lower, upper: uint64, width = 20): bool =
  ## Named numeric inputs fail before any file, logger, listener or integer narrowing.
  var value = 0'u64
  text.len <= width and unsignedValue(text, value) and value >= lower and value <= upper

func applies*(spec: OptionSpec, topic: string): bool =
  ## A command-specific field is valid only for an exact advertised command, never a prefix.
  topic in spec.commands.split('|')

func commandTopic*(arguments: seq[string]): string =
  ## Development subcommands are separate topics; no input is inferred from a directory or policy file.
  if arguments.len == 0: return ""
  if arguments[0] == "tiny-devnet" and arguments.len > 1 and not arguments[1].startsWith("-"):
    return arguments[0] & " " & arguments[1]
  arguments[0]

proc normalizeCommand*(arguments: seq[string], normalized: var seq[string],
    diagnostic: var string): bool =
  ## Validate token ownership atomically before producing owned canonical command and service arguments.
  normalized = @[]
  diagnostic = ""
  if arguments.len == 0: return true # The entry point prints overview help without opening services.
  let topic = commandTopic(arguments)
  let known = commandIndex(topic) >= 0
  let standalone = arguments[0].startsWith("--") and arguments[0] notin ["--version", "--help",
      "--selftest", "--io-selftest", "--mesh-selftest", "--integration-selftest",
      "--offload-selftest", "--offload-held-shutdown"]
  let start = if standalone: 0 elif arguments[0] == "tiny-devnet": 2 else: 1
  var fields = default(array[OptionSpecs.len, seq[string]])
  var service: seq[string] = @[]
  var bare: seq[string] = @[]
  var named = known
  var index = min(start, arguments.len)
  template refuse(reason: string): untyped =
    diagnostic = reason
    return false
  if not standalone and not known and arguments[0] notin ["--version", "--help", "-h", "--selftest",
      "--io-selftest", "--mesh-selftest", "--integration-selftest", "--offload-selftest",
          "--offload-held-shutdown"]:
    refuse("Unknown command: " & topic & "; use ragnarok --help")
  while index < arguments.len:
    let token = arguments[index]
    if not token.startsWith("--"):
      bare.add(token) # Collect a precise diagnostic without reinterpreting command words as option values.
      inc index
      continue
    let equal = token.find('=')
    let spelling = if equal >= 0: token[0..<equal] else: token
    let found = optionIndex(spelling)
    if found < 0: refuse("Unknown option: " & spelling)
    let spec = OptionSpecs[found]
    if fields[found].len > 0 and not spec.repeatable:
      refuse("Option may be supplied only once: " & spec.name)
    var value = "true"
    if spec.value.len == 0:
      if equal >= 0: refuse("Flag takes no value: " & spec.name)
    elif equal >= 0:
      value = token[equal+1..^1]
    else:
      if arguments.len-index < 2 or arguments[index+1].startsWith("--"):
        refuse("Missing " & spec.value & " after " & spec.name)
      inc index
      value = arguments[index]
    if value.len == 0: refuse("Empty value for " & spec.name)
    fields[found].add(value)
    if spec.commands.len > 0:
      if not known or not spec.applies(topic):
        refuse(spec.name & " is not available for " & topic)
      named = true
    else:
      let dedicated = topic.startsWith("tiny-devnet") or
        topic in ["fuzz", "serve-fuzz", "serve-fuzz-preset"]
      if dedicated and spec.name != "--log-level":
        refuse(spec.name & " is not available for " & topic)
      service.add(spec.name)
      if spec.value.len > 0: service.add(value)
    inc index
  if bare.len > 0:
    refuse("Unexpected positional argument: " & bare[0] & "; use named command flags (ragnarok " &
        topic & " --help)")
  if not named:
    if not standalone: normalized.add(arguments[0]) # Standalone information/selftest flags have no command values.
    for value in service: normalized.add(value)
    return true
  let dataValues = fields[optionIndex("--data-dir")]
  let directory = if dataValues.len > 0: dataValues[0] else: DefaultDataDirectory
  if directory.find(char(0)) >= 0: refuse("--data-dir must not contain NUL")
  let certGiven = fields[optionIndex("--net-cert")].len > 0
  let keyGiven = fields[optionIndex("--net-key")].len > 0
  if certGiven != keyGiven: refuse("Supply --net-cert and --net-key together, or omit both to generate a persistent identity")
  var recipe: seq[string] = @[]
  case topic
  of "server", "client":
    recipe = @["--net-port", "--net-cert", "--net-key", "--net-peer-key", "--net-alpn",
        "--net-timeout-ms", "--net-mode"]
  of "mesh":
    recipe = @["--net-local-port", "--net-remote-port", "--net-cert", "--net-key",
        "--net-local-key", "--net-peer-key", "--net-alpn", "--net-gate"]
  of "download", "download-current":
    recipe = @["--net-port", "--net-cert", "--net-key", "--net-peer-key", "--net-alpn",
        "--net-timeout-ms", "--download-policy"]
  of "history": discard # Query selectors belong to validated service controls, with no positional recipe.
  of "check-traces": recipe = @["--trace-policy", "--trace-genesis"]
  of "tiny-devnet init": recipe = @["--devnet-output"]
  of "tiny-devnet identity": recipe = @["--devnet-index"]
  of "tiny-devnet node": recipe = @["--devnet-dir", "--devnet-index", "--devnet-base-port",
      "--devnet-start-unix-ms", "--devnet-stop-slot", "--devnet-policy"]
  of "fuzz": recipe = @["--fuzz-state-writes", "--fuzz-state-write-bytes"]
  of "serve-fuzz": recipe = @["--fuzz-policy", "--fuzz-parameters", "--fuzz-state-writes", "--fuzz-state-write-bytes"]
  of "serve-fuzz-preset": recipe = @["--fuzz-policy", "--fuzz-state-writes", "--fuzz-state-write-bytes"]
  else: refuse("Unknown command: " & topic)
  var output: seq[string] = @[]
  for offset in 0..<start: output.add(arguments[offset]) # Only a known complete topic reaches this loop.
  for flag in recipe:
    let found = optionIndex(flag)
    var value = ""
    if fields[found].len > 0:
      value = fields[found][0]
    elif flag == "--net-cert": value = directory / "network" / "cert.pem"
    elif flag == "--net-key": value = directory / "network" / "key.pem"
    elif flag == "--net-peer-key" and topic != "server":
      refuse("Missing required option for " & topic & ": " & flag)
    elif flag == "--net-remote-port": value = $(DefaultNetworkPort+1)
    elif flag == "--net-timeout-ms" and topic == "server":
      let modes = fields[optionIndex("--net-mode")]
      let listening = modes.len == 0 or modes[0] == DefaultServerMode
      value = $(if listening: DefaultServerTimeoutMs else: DefaultTimeoutMs)
    elif OptionSpecs[found].fallback != OptionDefault.Required:
      value = OptionSpecs[found].defaultValue(topic) # One default supplies both help and normalized execution.
    else:
      refuse("Missing required option for " & topic & ": " & flag)
    case flag
    of "--net-port", "--net-local-port", "--net-remote-port":
      if not boundedNumber(value, 1, 65535, 5): refuse(flag & " must be in 1..65535")
    of "--net-timeout-ms":
      let modes = fields[optionIndex("--net-mode")]
      let maximum = if topic == "server" and modes.len > 0 and modes[0] == "offload":
          MaxOffloadTimeoutMs else: MaxPeerTimeoutMs
      let listening = topic == "server" and (modes.len == 0 or modes[0] == DefaultServerMode)
      if not boundedNumber(value, (if listening: 0'u64 else: 1'u64), uint64(maximum)):
        refuse(flag & " must be in 1.." & $maximum)
    of "--net-mode":
      if value == DefaultServerMode and topic != "server": refuse("--net-mode listen is only available for server")
    of "--devnet-index":
      if not boundedNumber(value, 0, 5): refuse(flag & " must be in 0..5")
    of "--devnet-base-port":
      if not boundedNumber(value, 1024, 65530, 5): refuse(flag & " must be in 1024..65530")
    of "--devnet-start-unix-ms":
      if not boundedNumber(value, 0, 4102444800000'u64): refuse(flag & " is outside the supported Unix origin range")
    of "--devnet-stop-slot":
      if not boundedNumber(value, 2, 64): refuse(flag & " must be in 2..64")
    of "--fuzz-state-writes", "--fuzz-state-write-bytes":
      if not boundedNumber(value, 0, high(uint64)): refuse(flag & " must be an unsigned decimal")
    else: discard # Paths, policy contents, network names and workload behavior belong to their owning handlers.
    output.add(value)
  if topic in ["download", "download-current"]:
    let peers = fields[optionIndex("--net-peer")]
    if peers.len >= MaxDownloadPeers: refuse("Too many --net-peer entries")
    for peer in peers:
      let colon = peer.find(':')
      if colon < 1 or colon == peer.len-1: refuse("Use --net-peer PORT:KEY_FILE")
      if not boundedNumber(peer[0..<colon], 1, 65535, 5): refuse("--net-peer port must be in 1..65535")
      output.add(peer[0..<colon])
      output.add(peer[colon+1..^1]) # A key path may itself contain colons; only the first delimiter separates the port.
  if topic == "check-traces":
    let traces = fields[optionIndex("--trace-file")]
    if traces.len == 0 or traces.len > MaxTraceSteps:
      refuse("Supply 1.." & $MaxTraceSteps & " --trace-file files in execution order")
    for trace in traces: output.add(trace)
  if topic in ["fuzz", "serve-fuzz", "serve-fuzz-preset"]:
    # Preserve only explicit overrides; omitted values must continue to resolve from the environment.
    for flag in ["--fuzz-spec", "--fuzz-data-path", "--fuzz-sock-path", "--fuzz-log-level"]:
      let values = fields[optionIndex(flag)]
      if values.len > 0:
        output.add(flag)
        output.add(values[0])
  let state = fields[optionIndex("--with-state")].len > 0
  let telemetry = fields[optionIndex("--with-telemetry")].len > 0
  if (state or telemetry) and fields[optionIndex("--chain")].len == 0:
    service.add("--chain"); service.add(DefaultChainFile)
  if topic in ["server", "client", "mesh", "download", "download-current"]:
    # Only selected features receive paths; omitted flags never enable state, disk or remote services.
    let lightValues = fields[optionIndex("--state-mode")]
    let light = lightValues.len > 0 and lightValues[0] == "light"
    let storage = fields[optionIndex("--state-storage")]
    let layouts = fields[optionIndex("--state-layout")]
    if state and storage.len > 0 and storage[0] == "disk":
      var layout = if light: StateDiskLayout.Paged else: DefaultStateLayout
      if layouts.len > 0:
        case layouts[0]
        of "journal": layout = StateDiskLayout.Journal
        of "managed": layout = StateDiskLayout.Managed
        of "paged": layout = StateDiskLayout.Paged
        else: refuse("Invalid --state-layout")
      elif light:
        service.add("--state-layout"); service.add("paged")
      if fields[optionIndex("--state-db")].len == 0:
        service.add("--state-db"); service.add(defaultDatabase(directory, light, layout))
    if fields[optionIndex("--with-management")].len > 0 and fields[optionIndex(
        "--management-socket")].len == 0:
      try:
        let root = if isAbsolute(directory): directory else: getCurrentDir() / directory
        service.add("--management-socket"); service.add(root / "management" / "admin.sock")
      except:
        refuse("Unable to resolve the default management socket directory")
  for value in service: output.add(value)
  normalized = output # No partly constructed command escapes an invalid required field or repeated list.
  true
