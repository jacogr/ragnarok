# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opt-in NimScript POC for pvm_reference_summary.py; validates evidence and renders Markdown.
## Run with nim e --hints:off pvm_reference_summary.nims -- REPORT.json OUTPUT.md.
import std/[json, os, sets, strutils, tables, unicode]

# Match Python truth testing for JSON values, including empty containers and zero.
proc truth(value: JsonNode): bool =
  case value.kind
  of JNull: false
  of JBool: value.getBool
  of JInt: value.getBiggestInt != 0
  of JFloat: value.getFloat != 0
  of JString: value.getStr.len != 0
  of JArray, JObject: value.len != 0

# Read an optional field without altering the report or treating explicit null as absent.
proc optional(value: JsonNode, key: string, fallback: JsonNode): JsonNode =
  if value.hasKey(key): value[key] else: fallback

# Reject schema mismatches explicitly rather than using getStr's empty-string fallback.
proc text(value: JsonNode): string =
  if value.kind != JString:
    raise newException(ValueError, "Expected string")
  result = value.getStr

# Python str() spellings for scalar report metadata; containers are outside the producer schema.
proc scalar(value: JsonNode): string =
  case value.kind
  of JString: value.getStr
  of JNull: "None"
  of JBool: (if value.getBool: "True" else: "False")
  of JInt: $value.getBiggestInt
  of JFloat: $value.getFloat
  of JArray, JObject:
    raise newException(ValueError, "Expected scalar metadata")

# Python str.split recognizes these Unicode whitespace codepoints, including ASCII separators.
proc whitespace(rune: Rune): bool =
  let n = int(rune)
  result = n in 9..13 or n in 28..32 or n in [0x85, 0xa0, 0x1680, 0x2028, 0x2029,
    0x202f, 0x205f, 0x3000] or n in 0x2000..0x200a

# Collapse whitespace, truncate by Unicode codepoints, then escape HTML and Markdown delimiters.
proc cell(value: JsonNode): string =
  var normalized = ""
  var pending = false
  for rune in scalar(value).runes:
    # Defer spaces to avoid leading/trailing whitespace and collapse consecutive runs.
    if whitespace(rune):
      pending = normalized.len != 0
    else:
      if pending:
        normalized.add(' ')
      normalized.add($rune)
      pending = false
  var count = 0
  result = ""
  for rune in normalized.runes:
    # Bound codepoints before escaping, matching the Python slice even for multibyte input.
    if count < 500:
      result.add($rune)
      inc count
  result = result.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    .replace("|", "\\|").replace("`", "'")

# Match the source's ASCII fullmatch patterns without importing an FFI-backed regex engine.
proc identity(value: string, suite: bool): bool =
  let start = if suite: 4 else: 1
  if (suite and (not value.startsWith("pvm_") or value.len <= 4)) or
      (not suite and (value.len == 0 or value[0] notin {'a'..'z'})):
    return false
  for i in start..<value.len:
    # Suite suffixes allow lowercase letters/underscores; binaries also allow digits/hyphens.
    if value[i] notin {'a'..'z', '_'} and (suite or value[i] notin {'0'..'9', '-'}):
      return false
  result = true

# Preserve missing, passing and failing process evidence independently of aggregate status.
proc verdict(stages: Table[string, BiggestInt], name: string): string =
  if name notin stages: "Not run"
  elif stages[name] == 0: "Pass"
  else: "Fail (exit " & $stages[name] & ")"

# Reject non-array optional fields while preserving absent-field defaults.
proc arrayField(report: JsonNode, key: string): JsonNode =
  result = optional(report, key, newJArray())
  if result.kind != JArray:
    raise newException(ValueError, "Expected array: " & key)

# Validate completeness and identity before emitting any summary that could imply success.
proc summarizeReference(report: JsonNode): string =
  let status = text(report["status"])
  if status notin ["running", "failed", "checks-passed"]:
    raise newException(ValueError, "Unknown PVM reference status")
  let plan = arrayField(report, "planned")
  var names: seq[string] = @[]
  var unique = initHashSet[string]()
  for item in plan:
    let name = text(item["binary"])
    if name in unique:
      raise newException(ValueError, "Duplicate PVM comparison identity")
    names.add(name)
    unique.incl(name)
  for item in plan:
    if not identity(text(item["binary"]), false) or not identity(text(item["suite"]), true):
      raise newException(ValueError, "Invalid PVM comparison identity")
  var expected = toHashSet(["build"])
  for name in names:
    for suffix in ["-reference", "-native"]:
      expected.incl(name & suffix)
  var stages = initTable[string, BiggestInt]()
  for item in arrayField(report, "checks"):
    let name = text(item["name"])
    if name notin expected or name in stages or item["exit_code"].kind != JInt:
      raise newException(ValueError, "Invalid or duplicate PVM process evidence")
    stages[name] = item["exit_code"].getBiggestInt
  var completed: seq[string] = @[]
  var seen = initHashSet[string]()
  for item in arrayField(report, "completed"):
    let name = text(item)
    if name in seen or name notin unique:
      raise newException(ValueError, "Invalid completed PVM comparisons")
    completed.add(name)
    seen.incl(name)
  if status == "checks-passed":
    # Require all zero exit codes, every expected process, and completion in planned order.
    var failed = false
    for code in stages.values:
      failed = failed or code != 0
    if names.len == 0 or stages.len != expected.len or failed or completed != names:
      raise newException(ValueError, "Incomplete or failed PVM evidence marked successful")
  var lines = @["## PVM reference comparisons", "", "**Status: " & cell(%status) & "**", "",
    "Correctness checks only. Execution durations are diagnostics; no speed comparison is claimed.",
    "", "Completed pairs: " & $completed.len & "/" & $plan.len & ".", "",
    "| Comparison | PolkaVM | Ragnarök native suite |", "| --- | --- | --- |"]
  for item in plan:
    let name = text(item["binary"])
    let role = if not truth(optional(item, "engine", %true)): " (backend neutral)" else: ""
    lines.add("| `" & name & "` | " & verdict(stages, name & "-reference") & role &
      " | `" & text(item["suite"]) & "`: " & verdict(stages, name & "-native") & " |")
  lines.add("")
  lines.add("Reference build: " & verdict(stages, "build") & ".")
  if truth(optional(report, "error", newJNull())):
    lines.add("")
    lines.add("Failure: " & cell(report["error"]))
  for key in ["head", "graypaper", "polkavm", "rust", "platform", "backend"]:
    if report.hasKey(key):
      lines.add("- " & key & ": " & cell(report[key]))
  lines.add("")
  lines.add("Download `summary.md`, `results.json` and the retained logs from this job’s " &
    "`pvm-reference` artifact for detailed evidence.")
  result = lines.join("\n") & "\n"

# The POC CLI owns only one render; Make and existing production summary callers stay unchanged.
when isMainModule:
  var args: seq[string] = @[]
  when defined(nimscript):
    # NimScript exposes the compiler command line; consume only arguments after the separator.
    var separated = false
    for i in 1..paramCount():
      if separated:
        args.add(paramStr(i))
      elif paramStr(i) == "--":
        separated = true
  else:
    args = commandLineParams()
  if args.len != 2:
    raise newException(ValueError, "Usage: -- REPORT.json OUTPUT.md")
  writeFile(args[1], summarizeReference(parseJson(readFile(args[0]))))
