# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deterministic grouped command help rendered from the parser's option catalog and defaults.

import std/strutils
import ./[cli_catalog, cli_commands]

proc wrapped(text: string, indent = 6): string =
  ## Wrap catalog descriptions at a stable terminal width without splitting an option spelling.
  let prefix = repeat(' ', indent)
  result = prefix
  var column = indent
  for word in text.splitWhitespace:
    if column > indent and column+word.len+1 > 88:
      result.add("\n" & prefix)
      column = indent
    if column > indent:
      result.add(' ')
      inc column
    result.add(word)
    column += word.len
  result.add('\n')

func visible(spec: OptionSpec, topic: string): bool =
  ## Hide unrelated service families from offline/conformance commands while retaining exact parser scope.
  if spec.commands.len > 0: return topic.len == 0 or spec.applies(topic)
  if topic.len == 0: return true
  if spec.group == OptionGroup.PVM and spec.name != "--pvm-backend": return false
  if topic in ["fuzz", "serve-fuzz", "serve-fuzz-preset"]:
    return spec.name == "--log-level"
  if topic.startsWith("tiny-devnet") or topic == "diagnostics": return spec.name == "--log-level"
  if topic == "check-traces":
    return spec.name in ["--log-level", "--chain", "--with-state", "--state-writes",
        "--state-write-bytes", "--trace-observations"]
  if spec.group == OptionGroup.Trace: return false
  if spec.group == OptionGroup.Download: return topic in ["download", "download-current"]
  if topic in ["download", "download-current"] and spec.group == OptionGroup.Telemetry: return false
  true

proc commandHelp*(topic = ""): string =
  ## Empty means the overview; an unknown topic returns no misleading successful help page.
  if topic.len > 0 and topic notin ["tiny-devnet", "diagnostics"] and commandIndex(topic) < 0: return ""
  result = "Usage: ragnarok " & (if topic.len == 0: "COMMAND [OPTIONS]" else: topic &
      " [OPTIONS]") & "\n"
  if topic.len == 0:
    result.add("       ragnarok --pvm-code FILE [--pvm-entry NAME] [--pvm-backend MODE] [OPTIONS]\n")
  if topic.len == 0 or topic == "tiny-devnet":
    result.add("\nCommands:\n")
    for command in CommandSpecs:
      if topic.len == 0 or command.name.startsWith(topic & " "):
        result.add("  " & command.name & "\n" & wrapped(command.description))
    result.add("\nUse ragnarok COMMAND --help for required command flags and examples.\n")
  elif topic == "diagnostics":
    result.add("\nDevelopment diagnostics (no service options):\n")
    result.add("  --selftest  --io-selftest  --mesh-selftest  --integration-selftest\n")
    result.add("  --offload-selftest  --offload-held-shutdown\n")
  else:
    result.add("\n" & wrapped(CommandSpecs[commandIndex(topic)].description, 0))
  if topic != "tiny-devnet":
    for ordinal in 0..ord(high(OptionGroup)):
      let group = OptionGroup(ordinal)
      var section = ""
      for spec in OptionSpecs:
        if spec.group != group or not visible(spec, topic): continue
        section.add("  " & spec.name & (if spec.value.len == 0: "" else: " " & spec.value))
        let fallback = spec.defaultValue
        if fallback.len > 0: section.add("  [default: " & fallback & "]")
        elif spec.commands.len > 0: section.add("  [required]")
        if spec.repeatable: section.add("  [repeatable]")
        section.add("\n" & wrapped(spec.description))
      if section.len > 0: result.add("\n" & OptionGroups[ordinal] & ":\n" & section)
  if topic.len == 0:
    result.add("\nInformation:\n  --help, -h     Show this overview.\n  --version      Show build and compiler identity.\n")
    result.add("  help COMMAND   Show command help (also COMMAND --help).\n  help diagnostics  List development selftests.\n")
    result.add("\nNamed command flags may be interleaved with service options.\n")
    result.add("Configuration options do not enable a service; use its --with-* flag.\n")
    result.add("\nExamples:\n  ragnarok server --net-port 4000 --net-cert node.pem --net-key node.key --net-peer-key - \\\n    --net-alpn NETWORK --with-ui\n  ragnarok check-traces --trace-policy policy.conf --trace-genesis genesis.bin \\\n    --trace-file step.bin --with-state --chain chain.json\n")
    result.add("\nConformance environment:\n  JAM_FUZZ=1 JAM_FUZZ_SPEC=tiny|full|fuzz JAM_FUZZ_DATA_PATH=DIR\n  JAM_FUZZ_SOCK_PATH=PATH; optional JAM_FUZZ_LOG_LEVEL.\n  Or use ragnarok fuzz with --fuzz-* overrides (flags take precedence).\n")
  elif topic == "server" or topic == "client":
    result.add("\nWorkload modes:\n  valid (ordinary exchange), clean, mixed, integrated, holder, idle, probe,\n  proof, light, invalid-proof, proof-cancel; server also accepts service,\n  integration, overload, offload and soak (harness-controlled).\n")
  elif topic in ["download", "download-current"]:
    result.add("\nRequires --with-state --chain FILE; telemetry is unavailable.\n")
    result.add("Repeat --net-peer PORT:KEY_FILE for additional peers.\n")
    if topic == "download-current": result.add("Use a ragnarok-current-download-policy-v1 policy; discovery must match its permissions.\n")
  elif topic == "check-traces":
    result.add("\nRequires --with-state --chain FILE. Repeat --trace-file FILE in execution order.\nNo listeners, disk storage or checkpoint import are enabled by this offline command.\n")
  if topic in ["fuzz", "serve-fuzz", "serve-fuzz-preset"]:
    result.add("\nExplicit --fuzz-* values override the corresponding JAM_FUZZ_* variables.\n")
    result.add("Omitted values use the environment; spec, data path and socket path are required.\n")
    result.add("JAM_FUZZ activates an environment-only launch; the fuzz commands also activate it.\n")
  if topic != "diagnostics":
    result.add("\nEvery command value requires a named flag; positional forms are rejected.\n")

proc helpRequest*(arguments: seq[string], topic: var string): bool =
  ## Help inspection precedes logging, fuzz environment selection, file IO and listener startup.
  topic = ""
  if arguments.len == 0: return true
  if arguments.len == 1 and arguments[0] in ["--help", "-h", "help"]: return true
  if arguments[0] == "help":
    for index in 1..<arguments.len:
      if index > 1: topic.add(' ')
      topic.add(arguments[index])
    return true
  if arguments[^1] in ["--help", "-h"]:
    topic = if arguments[0].startsWith("--pvm-"): "" else: commandTopic(arguments)
    return true
  false
