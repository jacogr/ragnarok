# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise the public offline command with independent configured chains, Genesis and complete signed trace files.
import std/[assertions, cmdline, strutils, syncio, parseutils]
import ../support/[trace_check_context, current_stf_population_reporting_context]
import ../../src/app/[options, trace_check_command, current_download_policy]
when defined(lateHistories):
  import ../support/current_stf_late_histories_context
elif defined(lateRetention):
  import ../support/current_stf_late_retention_context
elif defined(rotationIncarnations):
  import ../support/current_stf_rotation_incarnations_context

proc path(text: string): string =
  ## Decode only the hexadecimal pathname transport; actual files are read through production bounded EOF helpers.
  assert text.len mod 2 == 0
  result = newString(text.len div 2)
  for index in 0..<result.len:
    var octet: byte = 0
    assert parseHex(text.substr(index*2, index*2+1), octet) == 2
    result[index] = char(octet)
proc hex(bytes: openArray[byte]): string =
  ## Render copied verified roots without substituting an empty or failed result.
  const digits = "0123456789abcdef"
  result = ""
  for octet in bytes:
    result.add(digits[int(octet shr 4)])
    result.add(digits[int(octet and 15)])
proc main() {.raises.} =
  ## The maintained native fixture supplies resource-policy input only; every expected block/map and file hash was calculated independently first.
  var resource = traceCheckTestPolicy()
  if paramCount() == 3:
    assert paramStr(3) == "population"
    when defined(lateHistories):
      resource.candidate = lateHistoryLimits() # Explicit longer histories retain all seventeen genuine package identities.
    elif defined(lateRetention):
      resource.candidate = lateRetentionLimits() # Explicit late-code serial drains retain all five actual execution facts.
    elif defined(rotationIncarnations):
      resource.candidate = rotationIncarnationLimits() # Actual host programs and recreated namespaces use their qualified bounded policy.
    else:
      resource.candidate = populationReportingLimits() # Explicit three-core/nine-ceiling policy; default legacy command coverage stays unchanged.
  writeFile(paramStr(2), encodeCurrentDownloadPolicy(resource))
  for line in readFile(paramStr(1)).splitLines:
    if line.len == 0: continue # The request-file terminator contains no command.
    let fields = line.splitWhitespace()
    let observed = fields[0] == "O"
    let first = if observed: 2 else: 0
    assert fields.len >= first+3
    var arguments = @["check-traces", paramStr(2), path(fields[first+1])]
    for index in first+2..<fields.len: arguments.add(path(fields[
        index])) # Positional paths preserve spaces without shell interpretation.
    for item in ["--with-state", "--chain", path(fields[first]), "--state-writes", "1000",
        "--state-write-bytes", "1000000"]:
      arguments.add(item)
    if observed:
      arguments.add("--trace-observations")
      arguments.add(path(fields[1])) # Explicit observation directory is a separate comparison input, never a replacement expected trace.
    var options = default(Options)
    assert parseOptions(arguments, options)
    let checked = runTraceChecks(options)
    if checked.error == TraceCheckCommandError.None:
      echo "C ", checked.error, " ", checked.checkedBlocks, " ", hex(array[32, byte](
          checked.finalRoot))
    else:
      echo "C ", checked.error, " ", checked.checkedBlocks, " ", (if checked.detail.len ==
          0: "-" else: checked.detail) # Refusals expose bounded typed diagnostics and scalar progress, never a successful final root.
try:
  main() # I/O, parsing or unexpected command failures fail the complete independent comparison.
except:
  quit(2)
