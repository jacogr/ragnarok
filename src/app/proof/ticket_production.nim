# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private immutable signer capabilities own secret lifetime without imposing optional native signing linkage on ordinary proof-worker consumers.
## Source/signing aliases share the existing exact exclusive Services lease and retire before collection or joined teardown.
import std/assertions
import ../../jamnp-s/ticket_validation
import ../../jamnp-s/[audit_context, audit_validation]
from ../../codec/disputes import JudgeIndex
import ../../codec/tickets
import ../../codec/state/safrole
import ../../codec/header
import ../../bandersnatch/bandersnatch
import ../../crypto/validator_keys

type
  Produce = proc(context: pointer, source: TicketSource, local: StateEdKey, now: StateTime,
      connectivityEpoch: uint32, attempt: TicketAttempt): NetworkTicketResult[
          CheckedNetworkTicket] {.nimcall, raises: [].}
    ## The private factory binds only genuine registered-key RingVRF production.
  Announce = proc(context: pointer, source: AuditContext, ordinal: JudgeIndex,
      limits: AuditProofLimits): AuditValidationResult[CheckedAuditAnnouncement] {.nimcall.}
    ## The private factory binds the same registered JIP-5 key to initial CE144 production.
  Release = proc(context: pointer) {.nimcall, raises: [].} ## Last-owner release destroys the opaque private key before standard deallocation.
  SignerData = object ## Opaque resource storage uses private closed callbacks, not private runtime hooks or caller-supplied capabilities.
    context: nil pointer
    produce: nil Produce
    announce: nil Announce
    release: nil Release
    publicBytes: array[32, byte]
  SignerState = ref SignerData ## Acyclic immutable shared lifetime; no mutable public key owner escapes.
  TicketSigner* = object ## Default or failed configuration owns no signing capability.
    data: nil SignerState
  PrivateSigner = object ## Only the private allocation/release callbacks know this standard allocated layout.
    key: BsKey
  TicketSignerError* {.pure.} = enum ## Defaults and refused configuration expose no key or successful native cause.
    Uninitialized, None, Closed, Busy, Exhausted, WrongMode, KeyFailure
  TicketSignerResult* = object ## Only an actual successful private factory exposes an immutable signer owner.
    case status: TicketSignerError
    of None: completed: TicketSigner
    of KeyFailure: keyReason: BsError
    else: discard # Ordinary lifecycle/allocation refusal contains no fabricated child cause.
  ProductionData = ref object ## Detached immutable source and opaque signing lifetime contain no canonical map or Native stream authority.
    source: TicketSource
    signer: TicketSigner
    local: StateEdKey
    now: StateTime
    connectivityEpoch: uint32
    attempt: TicketAttempt
  TicketProductionJob* = object ## Only private capture binds a complete executable production input.
    data: nil ProductionData
  TicketProductionAdmission* = object ## Failed capture exposes no partial source or key-owning job.
    case status: NetworkTicketError
    of None: completed: TicketProductionJob
    else: discard                     # Defaults have no callable capability.
proc `=copy`(destination: var SignerData, source: SignerData) {.error.}
  ## Only immutable reference ownership may be shared; copying its underlying raw resource allocation is forbidden.
proc `=dup`(source: SignerData): SignerData {.error.}
  ## Private heap construction cannot duplicate an existing allocation either.
proc `=wasMoved`(data: var SignerData) {.nodestroy.} =
  ## Moved private resource storage cannot release the transferred allocation.
  data.context = nil
  data.produce = nil
  data.announce = nil
  data.release = nil
proc `=destroy`(data: SignerData) =
  ## Last ARC owner invokes exactly the factory-bound release callback.
  let release = data.release
  let context = data.context
  if release != nil and context != nil: release(context)
func valid*(signer: TicketSigner): bool =
  ## Observing an ordinary default cannot manufacture key material.
  signer.data != nil
proc signingPublic*(signer: TicketSigner): array[32, byte] {.requires: signer.valid.} =
  ## Public fingerprint permits idempotent local configuration without exposing secret or native lifetime controls.
  let data = signer.data
  assert data != nil
  data.publicBytes
func valid*(job: TicketProductionJob): bool =
  ## Only a complete private factory produces a captured input.
  job.data != nil
func error*(outcome: TicketSignerResult): TicketSignerError =
  ## Inspect configuration status before owner or native-cause extraction.
  outcome.status
func value*(outcome: TicketSignerResult): TicketSigner {.requires: outcome.status ==
    TicketSignerError.None.} =
  ## A successful configuration still grants no proof or registered-validator claim.
  outcome.completed
func keyError*(outcome: TicketSignerResult): BsError {.requires: outcome.status ==
    TicketSignerError.KeyFailure.} =
  ## Return only the actual failed derivation's cause.
  outcome.keyReason
proc releaseSigner(context: pointer) {.raises: [].} =
  ## The standard zero-initialized allocation is private and retired only after every leased job releases it.
  let owner = cast[ptr PrivateSigner](context)
  `=destroy`(owner[])
  dealloc(context)
proc produce(context: pointer, source: TicketSource, local: StateEdKey, now: StateTime,
    connectivityEpoch: uint32, attempt: TicketAttempt): NetworkTicketResult[CheckedNetworkTicket] =
  ## A stable private allocation borrows its opaque key only for this exact CPU activation.
  let owner = cast[ptr PrivateSigner](context)
  produceNetworkTicket(source, owner[].key, local, now, connectivityEpoch, attempt)
proc announce(context: pointer, source: AuditContext, ordinal: JudgeIndex,
    limits: AuditProofLimits): AuditValidationResult[CheckedAuditAnnouncement] =
  ## The opaque key is borrowed for the exact proof-worker activation.
  let owner = cast[ptr PrivateSigner](context)
  produceInitialAudit(source, ordinal, owner[].key, limits)
proc produceAuditAnnouncement*(signer: TicketSigner, source: AuditContext, ordinal: JudgeIndex,
    limits: AuditProofLimits): AuditValidationResult[CheckedAuditAnnouncement] =
  ## The closed signing operation accepts only source-bound initial audit inputs.
  let data = signer.data
  if data == nil: return default(AuditValidationResult[CheckedAuditAnnouncement])
  let produce = data.announce
  let context = data.context
  if produce == nil or context == nil: return default(AuditValidationResult[CheckedAuditAnnouncement])
  produce(context, source, ordinal, limits)
proc captureTicketSigner*(masterSeed: openArray[byte]): TicketSignerResult =
  ## Derive JIP-5 signing ownership; the caller retains/clears its borrowed master input and no seed bytes are retained here.
  let captured = deriveBandersnatchKey(masterSeed)
  if captured.error != BsError.None:
    return TicketSignerResult(status: TicketSignerError.KeyFailure, keyReason: captured.error)
  let public = publicKey(captured.value)
  if public.error != BsError.None:
    return TicketSignerResult(status: TicketSignerError.KeyFailure, keyReason: public.error)
  let raw = alloc0(sizeof(PrivateSigner))
  if raw == nil: return TicketSignerResult(status: TicketSignerError.Exhausted)
  let private = cast[ptr PrivateSigner](raw)
  private[].key = captured.value
  let state = SignerState(context: raw, produce: produce, announce: announce,
      release: releaseSigner, publicBytes: array[32, byte](public.value))
  TicketSignerResult(status: TicketSignerError.None, completed: TicketSigner(data: state))
func error*(outcome: TicketProductionAdmission): NetworkTicketError =
  ## Failed/default capture exposes no executable input.
  outcome.status
func value*(outcome: TicketProductionAdmission): TicketProductionJob {.requires: outcome.status ==
    NetworkTicketError.None.} =
  ## Production success remains asynchronous and separately typed.
  outcome.completed
proc captureTicketProduction*(source: TicketSource, signer: TicketSigner, local: StateEdKey,
    now: StateTime, connectivityEpoch: uint32, attempt: TicketAttempt): TicketProductionAdmission =
  ## Capture only private immutable capabilities; every host alias must retire before worker admission.
  if not source.valid: return TicketProductionAdmission(status: NetworkTicketError.NoSource)
  if not signer.valid: return TicketProductionAdmission(status: NetworkTicketError.NoSigner)
  if int(uint8(attempt)) >= source.networkAttempts: return TicketProductionAdmission(
      status: NetworkTicketError.InvalidPacket)
  TicketProductionAdmission(status: NetworkTicketError.None, completed: TicketProductionJob(data:
    ProductionData(source: source, signer: signer, local: local, now: now,
        connectivityEpoch: connectivityEpoch, attempt: attempt)))
proc executeTicketProduction*(job: TicketProductionJob): NetworkTicketResult[CheckedNetworkTicket] =
  ## The complete CPU activation retires all private key/source aliases before Done becomes observable.
  let data = job.data
  if data == nil: return ticketFailure[CheckedNetworkTicket](NetworkTicketError.NoSource)
  let signer = data.signer.data
  if signer == nil: return ticketFailure[CheckedNetworkTicket](NetworkTicketError.NoSigner)
  let produce = signer.produce
  let context = signer.context
  if produce == nil or context == nil: return ticketFailure[CheckedNetworkTicket](
      NetworkTicketError.NoSigner)
  produce(context, data.source, data.local, data.now, data.connectivityEpoch, data.attempt)
