# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default observation owners and unrelated command controls cannot expose prepared state.
import std/assertions
import std/syncio
import ../../support/state_trace_step_context
import ../../support/state_current_consecutive_context
import ../../../src/app/trace_import as app_trace_import
import ../../../src/app/chain as app_chain
import ../../../src/app/options as app_options
import ../../../src/state/trace_step as state_trace_step
import ../../../src/state/trace_state as state_trace_state
import ../../../src/codec/bounded as codec_bounded
proc main() =
  ## Validate default ownership and atomic option refusal; real positive complete maps live in the independent corpus.
  let chain = default(ApplicationChain)
  let step = default(TraceStep)
  let limits = currentConsecutiveLimits()
  assert prepareTraceObservation(chain, step, default(TraceState), [], limits).error ==
      TraceImportError.InvalidObservation
  var bytes = newSeq[byte](33)
  let observed = decodeTraceState(bytes, traceStepTestLimits().state, ByteLimit(33))
  assert observed.error == TraceStateError.None
  assert prepareTraceObservation(chain, step, observed.value, [], limits).error ==
      TraceImportError.InvalidTrace
  var options = default(Options)
  assert options.traceObservationsPath == ""
  let base = @["check-traces", "policy", "genesis", "step", "--with-state", "--chain", "chain.json", "--trace-observations"]
  var valid = base
  valid.add("observations with spaces")
  assert parseCanonicalOptions(valid, options)
  assert options.traceObservationsPath == "observations with spaces"
  for path in ["", "bad\npath"]:
    var arguments = base
    arguments.add(path) # Invalid bounded paths reset the complete options owner.
    assert not parseCanonicalOptions(arguments, options)
    assert options.traceObservationsPath == ""
  assert not parseCanonicalOptions(@["run", "--trace-observations", "observations"], options)
  echo "PASS trace observations: private owners and scoped bounded paths"
main()
