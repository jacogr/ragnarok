# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Closed assurance-signing jobs freeze one private TLS key, complete canonical source and native namespace through exact worker collection/join; no supplied possession flag or signing message is accepted.
import ../../jamnp-s/[work_signer, assurance_store, assurance_record, assurance_possession]
import ../../chain/genesis
import ../../codec/assurances

type
  SigningData = ref object ## Acyclic bounded input owns only immutable key/source/policy aliases and borrows the fixed archive address.
    signer: WorkSigner
    source: BlockSnapshotResult
    owner: ptr AssuranceStore
    chain: AssuranceChainId
    requested: AssuranceBits
    now: AssuranceTime
    limits: AssurancePossessionLimits
  AssuranceSigningJob* = object ## Only capture stages this one closed verify/renew/sign operation.
    data: nil SigningData
  AssuranceSigningJobError* {.pure.} = enum ## Refused/default capture carries no private key or mutable namespace capability.
    Uninitialized, None, Closed, Faulted, WrongChain, InvalidSigner, InvalidSource, InvalidPolicy
  AssuranceSigningAdmission* = object ## Only full bounded capture carries one staged immutable input owner.
    case status: AssuranceSigningJobError
    of None: completed: AssuranceSigningJob
    else: discard # Capture failure cannot retain a partial signer/source/input lease.
func error*(outcome: AssuranceSigningAdmission): AssuranceSigningJobError =
  ## Read the selected capture refusal before extracting a job.
  outcome.status
func value*(outcome: AssuranceSigningAdmission): AssuranceSigningJob {.requires: outcome.status ==
    AssuranceSigningJobError.None.} =
  ## Staging helpers retire this wrapper and every temporary ARC alias before native submission.
  outcome.completed
func valid*(job: AssuranceSigningJob): bool =
  ## A default job owns no signer, source or native borrow.
  job.data != nil
proc captureAssuranceSigning*(owner: var AssuranceStore, source: BlockSnapshotResult,
    signer: WorkSigner, chain: AssuranceChainId, requested: AssuranceBits, now: AssuranceTime,
    limits: AssurancePossessionLimits): AssuranceSigningAdmission =
  ## Capture performs no filesystem/proof/signature work; all aliases remain frozen and the native owner address stable through collection/join.
  if not owner.opened: return AssuranceSigningAdmission(status: AssuranceSigningJobError.Closed)
  if owner.faulted: return AssuranceSigningAdmission(status: AssuranceSigningJobError.Faulted)
  if not owner.matchesChain(chain): return AssuranceSigningAdmission(
      status: AssuranceSigningJobError.WrongChain)
  if source.error != GenesisError.None: return AssuranceSigningAdmission(
      status: AssuranceSigningJobError.InvalidSource)
  if signer.signerIdentity.error != WorkSignerError.None: return AssuranceSigningAdmission(
      status: AssuranceSigningJobError.InvalidSigner)
  if not limits.valid: return AssuranceSigningAdmission(
      status: AssuranceSigningJobError.InvalidPolicy)
  AssuranceSigningAdmission(status: AssuranceSigningJobError.None,
    completed: AssuranceSigningJob(data: SigningData(signer: signer, source: source,
      owner: addr owner,
      chain: chain, requested: requested, now: now, limits: limits)))
proc executeAssuranceSigning*(job: AssuranceSigningJob,
    control: AssuranceScanControl): AssuranceSigningResult[SignedAssurance] =
  ## The private signer performs the complete stored-possession check itself within this same synchronous native execution.
  let data = job.data
  if data == nil: return default(AssuranceSigningResult[SignedAssurance])
  data.signer.signStoredAssurance(data.owner[], data.source, data.chain, data.requested,
    data.now, data.limits, control)
