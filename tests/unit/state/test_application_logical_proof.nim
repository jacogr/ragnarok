# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Logical proof capture admits full-view copies before hashing and authenticates all chapters plus present-empty and absent values on the actual target.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_supplied_context, current_logical_proof_context]
import ../../../src/app/[logical_proof, proof_query]
import ../../../src/state/[current_logical, accumulation_current_update, proof_plan, planned_proof,
    proof_view, store]
import ../../../src/codec/bounded
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Capture must use cached extents without invoking cryptographic work.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe primitive work only after genuine complete qualification has finished.
proc main() {.raises.} =
  ## The actual original producer owns the selected posterior snapshot; header prior roots never substitute expected response roots.
  let fixture = collectedNativeFixture()
  let logical = suppliedNativeState(fixture)
  let selection = logicalProofPlan()
  let limits = LogicalProofLimits(blocks: ElementLimit(16), viewBytes: ByteLimit(33554432),
      query: logicalProofLimits())
  fail(1)
  let captured = captureLogicalProofQuery(logical, selection, limits)
  assert captured.error == LogicalProofError.None and calls() == 0
  var short = limits
  short.blocks = ElementLimit(0)
  assert captureLogicalProofQuery(logical, selection, short).error ==
      LogicalProofError.LimitExceeded
  short = limits
  short.viewBytes = ByteLimit(0)
  assert captureLogicalProofQuery(logical, selection, short).error ==
      LogicalProofError.LimitExceeded
  short = limits
  short.query.hashes = ProofHashLimit(0)
  assert captureLogicalProofQuery(logical, selection, short).error == LogicalProofError.QueryFailure
  let empty = default(CurrentLogicalState)
  assert captureLogicalProofQuery(empty, selection, limits).error ==
      LogicalProofError.InvalidLogical
  assert calls() == 0
  fail(0)
  let response = executeProofQuery(captured.value).value
  let root = logical.currentLogicalContext.value.state.commitment.root
  let view = decodePlannedProofs(response.bytes(limits.query.wireBytes).value, selection, root,
    limits.query.view, limits.query.proof, limits.query.aggregate, limits.query.wireBytes).value
  checkLogicalProof(logical, view, 2)
  echo "application-logical-proof: ok"
try:
  main()
except:
  quit(2) # No failed selection or primitive can authorize a partial proof query.
