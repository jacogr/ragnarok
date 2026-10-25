# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise the public offline command with independent configured chains, Genesis and complete signed trace files.
import std/[assertions, cmdline, strutils, syncio, parseutils]
import ../support/trace_check_context
import ../../src/app/[options, trace_check_command, current_download_policy]
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
  writeFile(paramStr(2), encodeCurrentDownloadPolicy(traceCheckTestPolicy()))
  for line in readFile(paramStr(1)).splitLines:
    if line.len == 0: continue # The request-file terminator contains no command.
    let fields = line.splitWhitespace()
    assert fields.len >= 3
    var arguments = @["check-traces", paramStr(2), path(fields[1])]
    for index in 2..<fields.len: arguments.add(path(fields[
        index])) # Positional paths preserve spaces without shell interpretation.
    for item in ["--with-state", "--chain", path(fields[0]), "--state-writes", "1000",
        "--state-write-bytes", "1000000"]:
      arguments.add(item)
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
