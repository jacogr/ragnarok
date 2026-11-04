# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fresh wire plus detached selected-root/profile facts enter one bounded CPU verification job.
## No canonical map/header alias, native handle or peer assertion is retained by the worker input.
import ../../jamnp-s/[read_stream, read_validation as read_verification]
import ../../chain/[provider, genesis]
import ../../codec/bounded

type
  VerificationData = ref object ## Private immutable input owns its own wire and fixed context before native submission.
    request: ReadRequest
    source: ReadSource
    wire: seq[byte]
    limits: ReadVerificationLimits
  ReadVerificationJob* = object ## Defaults grant no CPU work or selected-root authority.
    data: nil VerificationData
  ReadVerificationAdmission* = object ## Only admitted complete capture carries a job, never an input prefix.
    case status: ReadVerificationError
    of None: completed: ReadVerificationJob
    else: discard # Capture failures contain only their reason, not an alias or wire prefix.
func error*(outcome: ReadVerificationAdmission): ReadVerificationError =
  ## Read capture status without extracting a job.
  outcome.status
func value*(outcome: ReadVerificationAdmission): ReadVerificationJob {.requires: outcome.status ==
    ReadVerificationError.None.} =
  ## Transfer only a fully captured immutable request.
  outcome.completed
func valid*(job: ReadVerificationJob): bool =
  ## Job validity reads a scalar owner pointer, not any concurrently borrowed data.
  job.data != nil
proc captureReadVerification*(view: ChainView, request: ReadRequest, wire: openArray[byte],
    limits: ReadVerificationLimits): ReadVerificationAdmission =
  ## Bound input before copying, then retire all temporary canonical owners before the caller submits this job.
  if not request.valid: return ReadVerificationAdmission(
      status: ReadVerificationError.InvalidRequest)
  let minimum = request.minimumReplyBytes
  if uint64(limits.wireBytes) < minimum: return ReadVerificationAdmission(
      status: ReadVerificationError.InvalidConfig)
  if uint64(limits.wireBytes) > uint64(MaxReadReplyBytes): return ReadVerificationAdmission(
      status: ReadVerificationError.InvalidConfig)
  if uint64(wire.len) > uint64(limits.wireBytes): return ReadVerificationAdmission(
      status: ReadVerificationError.LimitExceeded)
  var source = default(ReadSource)
  if request.kind notin [ReadKind.Preimage, ReadKind.PreimageAnnouncement]:
    if view.fuzzOnly: return ReadVerificationAdmission(status: ReadVerificationError.NoSource)
    if view.retainedCount > 64: return ReadVerificationAdmission(
        status: ReadVerificationError.LimitExceeded)
    var selected = unavailableGenesis()
    if request.kind in [ReadKind.Blocks, ReadKind.Report]:
      selected = view.bestBlock # Block/report geometry comes from the local chain; queried content is not certified by that profile.
    else:
      let payload = request.payload
      var expected = default(array[32, byte])
      for index in 0..<32: expected[index] = payload[index]
      for index in 0..<view.retainedCount:
        let candidate = view.retainedBlockAt(RetainedBlockIndex(index))
        if candidate.error == GenesisError.None and array[32, byte](candidate.value.blockHash) == expected:
          selected = candidate
          break # Only bounded locally selected snapshots, never peer roots or an unbounded optional history index.
      if selected.error != GenesisError.None:
        let finalized = view.finalizedBlock
        if finalized.error == GenesisError.None and array[32, byte](finalized.value.blockHash) == expected:
          selected = finalized # Explicit retained finality can outlive the rolling body window.
    let captured = captureReadSource(selected)
    if captured.error != ReadVerificationError.None: return ReadVerificationAdmission(
        status: captured.error)
    source = captured.value
  var copied = newSeq[byte](wire.len)
  for index in 0..<wire.len: copied[index] = wire[index]
  ReadVerificationAdmission(status: ReadVerificationError.None, completed: ReadVerificationJob(
    data: VerificationData(request: request, source: source, wire: copied, limits: limits)))
proc executeReadVerification*(job: ReadVerificationJob): ReadVerificationResult[CheckedReadReply] =
  ## All CPU parsing/hash/proof work uses fresh input; no canonical adoption or native I/O runs here.
  let data = job.data
  if data == nil: return default(ReadVerificationResult[CheckedReadReply])
  verifyReadReply(data.request, data.wire, data.source, data.limits)
