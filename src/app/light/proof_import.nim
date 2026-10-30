# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Detached bounded light proof ingestion authenticates existing RPV1 transport against independently trusted current metadata.
## Capture does fixed framing/count admission and copying only; cryptographic work belongs on the bounded proof worker.
import std/assertions
import ./head as light_head
import ../checkpoint/identity as checkpoint_identity
import ../../state/trie_proof
import ../../state/proof/view as proof_view
import ../../codec/bounded
type
  LightProofImportLimits* = object ## Retained wire, per-proof, aggregate, view and primitive hash-call ceilings remain independent.
    proof*: StateProofLimits
    aggregate*: StateProofBatchLimits
    view*: ProofViewLimits
    wireBytes*: ByteLimit
    hashes*: ElementLimit
  ImportData = ref object ## Fixed trusted metadata and privately copied wire retain no native resource or canonical head/proof graph.
    selected: ApplicationCheckpointIdentity
    wire: seq[byte]
    limits: LightProofImportLimits
    estimated: uint64
  LightProofImport* = object ## An admitted request owns detached untrusted bytes, never a verified state prefix.
    data: nil ImportData
  ImportedData = ref object ## A successful whole batch is cryptographically bound to the exact trusted current checkpoint selected at capture.
    selected: ApplicationCheckpointIdentity
    verified: VerifiedStateProofBatch
  ImportedLightProofs* = object ## Verified facts alone never authorize a new root, header or canonical chain head.
    data: nil ImportedData
  LightImportError* {.pure.} = enum ## Defaults and failures expose reasons only; no partially verified evidence escapes.
    Uninitialized, None, InvalidSelection, InvalidFormat, LimitExceeded, ViewFailure, ProofFailure
  LightImportResult*[T] = object ## Only complete selected success grants its immutable request or verified batch.
    case status: LightImportError
    of None: completed: T
    of ViewFailure: viewCause: ProofViewError
    of ProofFailure: proofCause: StateProofError
    else: discard # Plain admission refusals own no payload.

func error*[T](outcome: LightImportResult[T]): LightImportError =
  ## Read the selected admission/decoding/authentication stage without exposing a prefix.
  outcome.status

func value*[T](outcome: LightImportResult[T]): T {.inline, requires: outcome.status ==
    LightImportError.None.} =
  ## Checked success alone exposes a completely admitted or authenticated owner.
  outcome.completed

func viewError*[T](outcome: LightImportResult[T]): ProofViewError {.requires: outcome.status ==
    LightImportError.ViewFailure.} =
  ## Preserve exact canonical framing, retention or view-capture refusal.
  outcome.viewCause

func proofError*[T](outcome: LightImportResult[T]): StateProofError {.requires: outcome.status ==
    LightImportError.ProofFailure.} =
  ## Cryptographic/path/value refusal never becomes an authenticated absent result.
  outcome.proofCause

func valid*(request: LightProofImport): bool =
  ## Default requests own no independently selected root or wire.
  request.data != nil

func valid*(proofs: ImportedLightProofs): bool =
  ## Only successful whole-request authentication grants usable facts.
  proofs.data != nil

proc identity*(proofs: ImportedLightProofs): ApplicationCheckpointIdentity {.requires: proofs.data != nil.} =
  ## Exact checkpoint binding lets the host refuse stale ingestion even when two headers share a posterior root.
  let data = proofs.data
  assert data != nil
  data.selected

proc batch*(proofs: ImportedLightProofs): VerifiedStateProofBatch {.requires: proofs.data != nil.} =
  ## Immutable genuinely verified facts retain no mutable transport or native pin.
  let data = proofs.data
  assert data != nil
  data.verified

proc estimatedHashes*(request: LightProofImport): ElementLimit {.requires: request.data != nil.} =
  ## Conservative admission counts both complete verification passes, independently of bounded wire/value bytes.
  let data = request.data
  assert data != nil
  ElementLimit(data.estimated)

proc captureLightProofImport*(head: LightApplicationHead, wire: openArray[byte],
    limits: LightProofImportLimits): LightImportResult[LightProofImport] =
  ## Fixed canonical RPV1 prefix/count checks precede private wire copying; no proof parsing or hashing occurs here.
  if not head.valid: return LightImportResult[LightProofImport](
      status: LightImportError.InvalidSelection) # Root authority must already exist independently of untrusted transport.
  if uint64(wire.len) > uint64(limits.wireBytes): return LightImportResult[LightProofImport](
      status: LightImportError.LimitExceeded) # Copy admission precedes all allocation.
  if wire.len < 8: return LightImportResult[LightProofImport](
      status: LightImportError.InvalidFormat) # Prove the complete fixed prefix before reading any field.
  if wire[0] != byte('R') or wire[1] != byte('P') or wire[2] != byte('V') or wire[3] != byte(
      '1'): return LightImportResult[LightProofImport](
      status: LightImportError.InvalidFormat) # No alternative framing or root-bearing wire format is inferred.
  var count = 0'u64
  for index in 0..<4: count = count or (uint64(wire[4+index]) shl (8*index)) # E4 is widened before shifts.
  if count > uint64(limits.aggregate.items) or count > uint64(
      limits.view.items): return LightImportResult[LightProofImport](
      status: LightImportError.LimitExceeded) # Whole-batch and retained-view counts remain independent.
  if count > uint64((wire.len-8) div 45): return LightImportResult[LightProofImport](
      status: LightImportError.InvalidFormat) # Every record needs its fixed key/length plus minimum RSP1 header.
  if count > uint64(high(int) div sizeof(StateProofQuery)): return LightImportResult[
      LightProofImport](
      status: LightImportError.LimitExceeded) # Host descriptor allocation must remain representable.
  let perQuery = 2*(min(uint64(limits.proof.nodes),
      249'u64)+2) # At most 502 calls covers decode verification and final batch recapture.
  if count > uint64(limits.hashes) div perQuery: return LightImportResult[LightProofImport](
      status: LightImportError.LimitExceeded) # Division proves the later multiplication cannot wrap or exceed caller work authority.
  var copied = newSeq[byte](wire.len)
  for index in 0..<copied.len: copied[index] = wire[
      index] # Caller mutations cannot alter the worker's admitted bytes.
  LightImportResult[LightProofImport](status: LightImportError.None,
    completed: LightProofImport(data: ImportData(selected: head.current.value.identity,
      wire: copied, limits: limits, estimated: count*perQuery)))

proc executeLightProofImport*(request: LightProofImport): LightImportResult[ImportedLightProofs] =
  ## Decode/authenticate every fact privately under independent root authority, then return one exact bound verified batch.
  let data = request.data
  if data == nil: return LightImportResult[ImportedLightProofs](
      status: LightImportError.Uninitialized) # Defaults cannot fabricate an empty verified import.
  let limits = data.limits
  let decoded = decodeProofView(data.wire, data.selected.stateRoot, limits.view,
    limits.proof, limits.aggregate, limits.wireBytes)
  if decoded.error == ProofViewError.ProofFailure: return LightImportResult[ImportedLightProofs](
      status: LightImportError.ProofFailure,
      proofCause: decoded.proofError) # No earlier successful fact escapes a later proof failure.
  if decoded.error != ProofViewError.None: return LightImportResult[ImportedLightProofs](
      status: LightImportError.ViewFailure,
      viewCause: decoded.error) # Preserve strict canonical framing and capture limits.
  let raw = exportProofQueries(decoded.value, limits.view)
  if raw.error != ProofViewError.None: return LightImportResult[ImportedLightProofs](
      status: LightImportError.ViewFailure,
      viewCause: raw.error) # Immutable witness handles cross only a bounded detached descriptor array.
  let verified = verifyStateProofs(raw.value, data.selected.stateRoot, limits.proof,
      limits.aggregate)
  if verified.error != StateProofError.None: return LightImportResult[ImportedLightProofs](
      status: LightImportError.ProofFailure,
      proofCause: verified.error) # The second bounded verification grants the ordinary state-layer batch type.
  LightImportResult[ImportedLightProofs](status: LightImportError.None,
    completed: ImportedLightProofs(data: ImportedData(selected: data.selected,
        verified: verified.value)))
