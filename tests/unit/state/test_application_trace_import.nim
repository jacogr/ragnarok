# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/missing actual-chain boundaries cannot turn valid published wire into installation authority.
import std/[assertions, envvars, syncio]
import ../../support/[trace_step_context, current_consecutive_context]
import "../../../src/app/trace/import" as trace_import
import ../../../src/app/chain
import ../../../src/state/trace/step as trace_step
proc main() {.raises.} =
  ## Real independent trace framing still needs a configured selected application parent.
  let missing = default(TraceImportResult)
  assert missing.error == TraceImportError.Uninitialized
  let chain = default(ApplicationChain)
  let limits = currentConsecutiveLimits()
  let invalid = default(TraceStep)
  assert prepareTraceImport(chain, invalid, [], limits).error == TraceImportError.InvalidTrace
  let path = getEnv("RAGNAROK_STATE_TRACE_STEP")
  assert path.len != 0
  let text = readFile(path)
  var bytes = newSeq[byte](text.len)
  for index in 0..<text.len: bytes[index] = byte(text[
      index]) # The fixture is an independent signed trace, not an implicit selected-parent trust source.
  let parsed = decodeTraceStep(bytes, traceStepTestLimits())
  assert parsed.error == TraceStepError.None
  assert prepareTraceImport(chain, parsed.value, [], limits).error == TraceImportError.MissingParent
  echo "PASS application TraceStep import: explicit actual-parent boundary"
try:
  main() # Missing configuration and I/O failures fail the entire native suite.
except:
  quit(2)
