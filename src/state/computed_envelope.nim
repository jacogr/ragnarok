# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Materialize exact verified computed guarantees and canonical unique reporter identities.

import ../chain/parameters as chain_parameters
import ../codec/bounded as codec_bounded
import ../codec/assurances as codec_assurances
import ../codec/guarantees as codec_guarantees
import ../codec/report_owned as codec_report_owned
import ../codec/owned as codec_owned
import ../codec/state_safrole as codec_state_safrole
import ./computed_credentials as state_computed_credentials
import ./computed_guarantors as state_computed_guarantors
import ./computed_roster as state_computed_roster
import ./computed_transition as state_computed_transition
import ./computed_profile as state_computed_profile
import ./computed_lookup as state_computed_lookup
import ./computed_recent as state_computed_recent
import ./computed_state as state_computed_state
import ./computed_links as state_computed_links
import ./computed_guarantee as state_computed_guarantee
import ./computed_report as state_computed_report

type
  ComputedEnvelopeError* {.pure.} = enum ## Refusals carry no partial guarantee, wire or reporter set.
    Uninitialized, None, InvalidSource, LimitExceeded, InvalidReport, EncodingFailure, InvalidIndex
  ComputedEnvelopeLimits* = object ## Independent complete report-copy, guarantee-wire and unique-reporter ceilings.
    reportBytes*, bytes*: ByteLimit
    reporters*: ElementLimit
  ComputedReporterIndex* = distinct uint64 ## Canonical reporter-set ordinal differs from credential and validator indices.
  ComputedEnvelopeInfo* = object ## Fixed copied lengths/counts grant no certificate replacement authority.
    reportBytes*, bytes*: uint64
    reporters*: int
  ComputedEnvelopeData = ref object ## Immutable acyclic source sharing binds exact canonical output and sorted unique reporters.
    source: CredentialedComputedReport
    guarantee: Guarantee
    wire: seq[byte]
    reporters: array[3, StateEdKey]
    info: ComputedEnvelopeInfo
  ComputedGuaranteeEnvelope* = object ## Canonical output and credentials do not establish block inclusion or complete report admission.
    data: nil ComputedEnvelopeData
  ComputedEnvelopeResult*[T] = object ## Private complete success alone carries application data.
    case status: ComputedEnvelopeError
    of None:
      completed: T
    else:
      discard                         # Defaults and refusals expose reasons alone.

func error*[T](outcome: ComputedEnvelopeResult[T]): ComputedEnvelopeError =
  ## Inspect selected status without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedEnvelopeResult[T]): T
    {.requires: outcome.status == ComputedEnvelopeError.None.} =
  ## Preserve successful extraction contracts under optimized compilation.
  outcome.completed
proc computedEnvelopeSource*(bound: ComputedGuaranteeEnvelope): ComputedEnvelopeResult[
    CredentialedComputedReport] =
  ## Share exact verified credential, assignment and original computation provenance.
  let data = bound.data
  if data == nil: return ComputedEnvelopeResult[CredentialedComputedReport](
      status: ComputedEnvelopeError.Uninitialized)
  ComputedEnvelopeResult[CredentialedComputedReport](status: ComputedEnvelopeError.None,
      completed: data.source)
proc computedEnvelopeInfo*(bound: ComputedGuaranteeEnvelope): ComputedEnvelopeResult[
    ComputedEnvelopeInfo] =
  ## Copy complete byte/set facts without mutable backing storage.
  let data = bound.data
  if data == nil: return ComputedEnvelopeResult[ComputedEnvelopeInfo](
      status: ComputedEnvelopeError.Uninitialized)
  ComputedEnvelopeResult[ComputedEnvelopeInfo](status: ComputedEnvelopeError.None,
      completed: data.info)
proc computedEnvelopeGuarantee*(bound: ComputedGuaranteeEnvelope): ComputedEnvelopeResult[Guarantee] =
  ## Copy fixed metadata/credentials and share only the independently captured immutable report.
  let data = bound.data
  if data == nil: return ComputedEnvelopeResult[Guarantee](
      status: ComputedEnvelopeError.Uninitialized)
  ComputedEnvelopeResult[Guarantee](status: ComputedEnvelopeError.None, completed: data.guarantee)
proc computedEnvelopeBytes*(bound: ComputedGuaranteeEnvelope): ComputedEnvelopeResult[seq[byte]] =
  ## Return independent canonical bytes; caller mutation cannot alter the retained encoding.
  let data = bound.data
  if data == nil: return ComputedEnvelopeResult[seq[byte]](
      status: ComputedEnvelopeError.Uninitialized)
  var copied = newSeq[byte](data.wire.len)
  for i in 0..<copied.len: copied[i] = data.wire[i] # Copy exactly the validated whole standalone guarantee.
  ComputedEnvelopeResult[seq[byte]](status: ComputedEnvelopeError.None, completed: copied)
proc computedEnvelopeReporterAt*(bound: ComputedGuaranteeEnvelope,
    index: ComputedReporterIndex): ComputedEnvelopeResult[StateEdKey] =
  ## Copy one lexicographically ordered unique key after checking the owner-relative ordinal.
  let data = bound.data
  if data == nil: return ComputedEnvelopeResult[StateEdKey](
      status: ComputedEnvelopeError.Uninitialized)
  if uint64(index) >= uint64(data.info.reporters): return ComputedEnvelopeResult[StateEdKey](
      status: ComputedEnvelopeError.InvalidIndex)
  ComputedEnvelopeResult[StateEdKey](status: ComputedEnvelopeError.None, completed: data.reporters[
      int(uint64(index))])
func compare(left, right: StateEdKey): int =
  ## Compare every identity byte in deterministic lexicographic order, without interpreting curve encodings.
  let a = array[32, byte](left)
  let b = array[32, byte](right)
  for i in 0..<32:
    if a[i] < b[i]: return -1 # First smaller octet orders the complete key first.
    if a[i] > b[i]: return 1 # First greater octet orders the complete key later.
  0
proc prepareComputedEnvelope*(source: CredentialedComputedReport,
    limits: ComputedEnvelopeLimits): ComputedEnvelopeResult[ComputedGuaranteeEnvelope] =
  ## Preflight all byte/set policies, then capture exact original report and use the maintained canonical encoder without crypto work.
  template fail(reason: ComputedEnvelopeError) =
    return ComputedEnvelopeResult[ComputedGuaranteeEnvelope](status: reason)
  if source.computedCredentialSource.error != ComputedCredentialError.None: fail(
      ComputedEnvelopeError.InvalidSource)
  let context = source.computedCredentialSource.value
  let configured = context.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value
  let parameters = configured.computedProfileContext.value.parameters
  let transcript = configured.computedProfileSource.value.computedLookupSource.value.computedRecentSource.value.computedStateSource.value.computedLinkSource.value
  let report = transcript.computedGuaranteeReport.value
  let length = report.computedReportInfo.value.length
  let info = source.computedCredentialInfo.value # Successful source proves two/three ordered complete records.
  let suffix = uint64(5+66*info.credentials)
  if length > uint64(limits.reportBytes): fail(ComputedEnvelopeError.LimitExceeded)
  if length > uint64(high(int))-suffix: fail(ComputedEnvelopeError.LimitExceeded) # Prove native addition before allocating or narrowing.
  let size = length+suffix
  if size > uint64(limits.bytes): fail(ComputedEnvelopeError.LimitExceeded)
  var records = default(array[3, GuaranteeCredential])
  var reporters = default(array[3, StateEdKey])
  var count = 0
  for i in 0..<info.credentials:
    records[i] = source.computedCredentialAt(ComputedCredentialIndex(uint64(i))).value
    let assigned = context.computedGuarantorAt(info.slot, records[i].validator)
    if assigned.error != ComputedGuarantorError.None: fail(ComputedEnvelopeError.InvalidSource)
    let key = assigned.value.validator.ed25519
    var position = 0
    while position < count and compare(reporters[position], key) < 0:
      inc position # Find canonical insertion point in at most three fixed identities.
    if position < count and compare(reporters[position], key) == 0:
      continue # Duplicate actual key consumes no additional reporter capacity, despite distinct credential indices.
    if uint64(count) >= uint64(limits.reporters): fail(ComputedEnvelopeError.LimitExceeded)
    var cursor = count
    while cursor > position:
      let prior = reporters[cursor-1]
      reporters[cursor] = prior # Copy fixed identities without aliasing overlapping elements.
      dec cursor
    reporters[position] = key
    inc count # At most info.credentials<=3 insertions prove every fixed-array access.
  let cores = parameters.get(coreCount) # Completed source proves 2<=cores<=341 before multiplying the structural ceiling.
  var captured = default(OwnedReport)
  block:
    # Retire the temporary original wire before allocating the final guarantee encoding.
    let original = report.computedReportBytes.value
    let decoded = decodeOwnedReport(original, cores)
    if decoded.error != OwnershipError.None: fail(ComputedEnvelopeError.InvalidReport)
    captured = decoded.value
    if uint64(ownedReportInfo(captured).value.consumed) != length: fail(
        ComputedEnvelopeError.InvalidReport)
  let guarantee = Guarantee(report: captured, slot: info.slot, credentials: records,
      credentialCount: info.credentials)
  let config = GuaranteeConfig(cores: CoreCount(cores), validators: ValidatorCount(3*cores),
      maxBytes: ByteLimit(size))
  let measured = measureGuarantee(guarantee, config)
  if measured.error != GuaranteeError.None: fail(ComputedEnvelopeError.EncodingFailure)
  if uint64(measured.value) != size: fail(ComputedEnvelopeError.EncodingFailure)
  let encoded = encodeGuaranteeValue(guarantee, config)
  if encoded.error != GuaranteeError.None: fail(ComputedEnvelopeError.EncodingFailure)
  if uint64(encoded.value.len) != size: fail(ComputedEnvelopeError.EncodingFailure)
  ComputedEnvelopeResult[ComputedGuaranteeEnvelope](status: ComputedEnvelopeError.None,
    completed: ComputedGuaranteeEnvelope(data: ComputedEnvelopeData(source: source,
      guarantee: guarantee,
      wire: encoded.value, reporters: reporters,
      info: ComputedEnvelopeInfo(reportBytes: length, bytes: size, reporters: count))))
