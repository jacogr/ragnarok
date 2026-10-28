# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_computed_report_arc_release"}

## Complete independent report wire, exact policy and original context/trace/digest provenance.

import std/assertions
import std/syncio
import ../../../src/state/computed_report as state_computed_report
import ../../../src/state/availability_specifier as state_availability_specifier
import ../../../src/state/export_erasure as state_export_erasure
import ../../../src/state/bundle_erasure as state_bundle_erasure
import ../../../src/state/erasure_layout as state_erasure_layout
import ../../../src/state/auditable_bundle as state_auditable_bundle
import ../../../src/state/input_refinement as state_input_refinement
import ../../../src/state/report_identity as state_report_identity
import ../../../src/state/authorized_refinement as state_authorized_refinement
import ../../../src/state/authorization_invocation as state_authorization_invocation
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/work_report as codec_work_report
import ../../../src/chain/parameters as chain_parameters
import ../../../src/crypto/primitives as crypto_primitives
import ../../support/pvm_computed_report
import ../../support/pvm_computed_report_vectors
import ../../support/testing_arc_evidence

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse new hashing after original execution/availability to prove assembly is pure serialization.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe actual primitive attempts without manufacturing a successful hash.
proc expect[T](outcome: ComputedReportResult[T], reason: ComputedReportError) =
  ## Compare exact refusal alternatives without selecting any encoded prefix.
  assert outcome.error == reason, "computed report reason"
proc sameWire(actual, expected: openArray[byte]) =
  ## Report the first independent literal mismatch precisely for gas/encoding/source diagnosis.
  if actual.len != expected.len:
    echo "report length actual=", actual.len, " expected=", expected.len
  for index in 0..<min(actual.len, expected.len):
    if actual[index] != expected[index]:
      echo "report byte ", index, " actual=", actual[index], " expected=", expected[index]
      assert false, "independent complete report byte"
  assert actual.len == expected.len, "complete report length"
proc verify(source: AvailabilityCommitment, expected: openArray[byte], hash: array[32,
    byte]): ComputedWorkReport =
  ## Compare independent complete wire and re-encode through the established complete-report codec.
  let done = prepareComputedReport(source, ByteLimit(100000)).value
  let info = done.computedReportInfo.value
  let bytes = done.computedReportBytes.value
  sameWire(bytes, expected)
  assert array[32, byte](blake2b256(bytes).value) == hash, "independent full report hash"
  assert info.length == uint64(bytes.len), "exact retained report extent"
  let identity = source.availabilitySource.value.exportErasureSource.value.bundleErasureSource.value.layoutSource.value.bundleSource.value.inputRefinementIdentity.value
  let auth = identity.identitySource.value.authorizedSource.value
  let cores = auth.authorizationParameters.value.get(coreCount)
  let decoded = decodeReportBorrowed(bytes, cores)
  assert decoded.error == CompositeError.None, "complete canonical report decode"
  assert decoded.consumed == bytes.len, "no suffix or omitted final digest metric"
  let report = decoded.value
  var encoded = newSeq[byte](bytes.len)
  let written = encodeReportBorrowed(report, bytes, cores, encoded)
  assert written.error == CompositeError.None, "complete canonical report re-encode"
  assert encoded == bytes, "canonical decode/re-encode identity"
  assert report.header.packageHash.bytes == source.availabilityInfo.value.specifier.packageHash.bytes, "original package hash"
  assert uint64(report.core) == uint64(identity.identityInfo.value.core), "original nominated core"
  assert report.authorizer.bytes == identity.identityInfo.value.authorizer.bytes, "original authorizer identity"
  assert uint64(report.authGas) == uint64(info.authorizationGasUsed), "original authorization gas"
  assert report.prerequisiteCount == info.prerequisites, "original context prerequisite count"
  assert report.lookupCount == info.lookupCount, "original exact lookup count"
  assert report.digestCount == info.items, "original ordered digest count"
  assert uint64(report.authOutput.length) == info.traceBytes, "original authorization trace extent"
  let exact = info.length+info.workspaceBytes
  expect(prepareComputedReport(source, ByteLimit(exact)), ComputedReportError.None)
  expect(prepareComputedReport(source, ByteLimit(exact-1)), ComputedReportError.LimitExceeded)
  expect(prepareComputedReport(source, ByteLimit(0)), ComputedReportError.LimitExceeded)
  assert done.computedReportSource.value.availabilityInfo.value.specifier.packageHash.bytes ==
      report.header.packageHash.bytes, "exact retained original source"
  done
let source = computedAvailability(0)
let empty = verify(source, EmptyReport, EmptyHash)
assert empty.computedReportInfo.value.blobBytes == 2, "halt authorizer returns its original E2 core argument"
discard verify(computedAvailability(1), SingleReport, SingleHash)
let mixed = verify(computedAvailability(3), MixedReport, MixedHash)
assert mixed.computedReportInfo.value.items == 3, "normalized error digests retain original order"
discard verify(computedAvailability(65), PagedReport, PagedHash)
let contextSource = computedAvailability(4)
let context = verify(contextSource, ContextReport, ContextHash)
let facts = context.computedReportInfo.value
assert facts.prerequisites == 2, "two original canonical prerequisites"
assert facts.lookupCount == 1, "original exact package-to-root lookup"
assert facts.traceBytes == 3, "nonempty original authorization trace"
assert facts.blobBytes == 9, "trace plus both successful outputs"
assert facts.workspaceBytes == 12, "shared pool plus largest extracted blob"
# Refusing original configured shard/core domains cannot be bypassed by a caller-provided replacement core ceiling.
let narrow = narrowReportSource()
expect(prepareComputedReport(narrow, ByteLimit(100000)), ComputedReportError.InvalidReport)
expect(prepareComputedReport(narrow, ByteLimit(0)), ComputedReportError.InvalidReport)
# Caller copies of canonical bytes and fixed header facts cannot alter retained wire or provenance.
var copied = context.computedReportBytes.value
copied[0] = copied[0] xor 1
var changed = context.computedReportInfo.value
changed.header.packageHash.bytes[0] = changed.header.packageHash.bytes[0] xor 1
changed.length = 0
sameWire(context.computedReportBytes.value, ContextReport)
assert context.computedReportInfo.value.length == uint64(ContextReport.len), "metadata copy isolation"
expect(default(ComputedWorkReport).computedReportInfo, ComputedReportError.Uninitialized)
expect(default(ComputedWorkReport).computedReportSource, ComputedReportError.Uninitialized)
expect(default(ComputedWorkReport).computedReportBytes, ComputedReportError.Uninitialized)
expect(default(ComputedReportResult[ComputedWorkReport]), ComputedReportError.Uninitialized)
expect(prepareComputedReport(default(AvailabilityCommitment), ByteLimit(0)),
    ComputedReportError.InvalidSource)
reset(1)
expect(prepareComputedReport(contextSource, ByteLimit(100000)), ComputedReportError.None)
expect(prepareComputedReport(contextSource, ByteLimit(0)), ComputedReportError.LimitExceeded)
assert hashes() == 0, "complete report assembly performs no hashes"
reset(0)
proc detached(): ComputedWorkReport =
  ## Retain complete wire and original execution after every temporary preparation handle retires.
  prepareComputedReport(computedAvailability(0), ByteLimit(100000)).value
sameWire(detached().computedReportBytes.value, EmptyReport)
proc cycle() =
  ## Release complete wire, trace/output pool, extracted copies and refused candidates every iteration.
  let done = prepareComputedReport(contextSource, ByteLimit(100000)).value
  sameWire(done.computedReportBytes.value, ContextReport)
  expect(prepareComputedReport(contextSource, ByteLimit(facts.length+facts.workspaceBytes-1)),
      ComputedReportError.LimitExceeded)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after, "computed report ARC release"
recordArcRelease("pvm_computed_report", 1000, before, after)
echo "PVM computed report passed"
echo "ARC_RELEASE cycles=1000 unchanged"
