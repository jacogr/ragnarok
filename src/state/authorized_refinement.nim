# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind successful bounded authorization to its own ordered refinement and canonical digest projection.
## This execution owner is not an availability certificate; state composition/publication remains separate.

import ../codec/[composite, work_digest, work_report]
import ../pvm/host_fetch
import ./[authorization_invocation, refinement_report, refinement_dispatch, refinement_digest]

type
  AuthorizedRefinementError* {.pure.} = enum ## Refusals contain no partial report/digests or invented source authority.
    Uninitialized, None, InvalidAuthorization, AuthorizationRejected, TraceTooLarge,
    LimitExceeded, RefinementFailure, DigestFailure
  AuthorizedRefinementLimits* = object ## Trace-copy policy supplements independent existing child execution/projection caps.
    trace*: FetchTraceLimit
    refinement*: RefinementReportLimits
    digests*: RefinementDigestLimits
  AuthorizedRefinementInfo* = object ## Copied facts preserve separate authorization gas and package-level result counts.
    core*: CoreIndex
    host*: ServiceIndex
    anchor*: LookupSlot
    authorizationGasUsed*: Gas
    traceBytes*, blobBytes*: uint64
    items*: int
    exports*: ExportCount
  AuthorizedData = ref object ## Acyclic private ownership binds matching auth, report and digest sources without caller substitution.
    authorization: AuthorizationInvocation
    digests: RefinementDigests
    info: AuthorizedRefinementInfo
  AuthorizedRefinement* = object ## Default is invalid; even an empty successful trace requires genuine completed authorization.
    data: nil AuthorizedData
  AuthorizedRefinementResult*[T] = object ## Only the selected success/reason alternative exposes its complete value or detail.
    case status: AuthorizedRefinementError
    of None:
      completed: T
    of AuthorizationRejected:
      authorizationReason: WorkKind
    of RefinementFailure:
      refinementReason: RefinementReportResult[RefinedPackage]
    of DigestFailure:
      digestReason: RefinementDigestError
    else:
      discard # Simple local/protocol refusals expose neither a partial owner nor unrelated stage detail.

func error*[T](outcome: AuthorizedRefinementResult[T]): AuthorizedRefinementError =
  ## Inspect the selected alternative without writable tag access.
  outcome.status
func value*[T](outcome: AuthorizedRefinementResult[T]): T
    {.requires: outcome.status == AuthorizedRefinementError.None.} =
  ## Extract only complete bound authorization/refinement/digests.
  outcome.completed
func authorizationKind*[T](outcome: AuthorizedRefinementResult[T]): WorkKind
    {.requires: outcome.status == AuthorizedRefinementError.AuthorizationRejected.} =
  ## Preserve the exact protocol authorization work error without an invented successful trace.
  outcome.authorizationReason
func refinementError*[T](outcome: AuthorizedRefinementResult[T]): RefinementReportResult[RefinedPackage]
    {.requires: outcome.status == AuthorizedRefinementError.RefinementFailure.} =
  ## Preserve nested preparation/host/engine refusal detail without any earlier completed item prefix.
  outcome.refinementReason
func digestError*[T](outcome: AuthorizedRefinementResult[T]): RefinementDigestError
    {.requires: outcome.status == AuthorizedRefinementError.DigestFailure.} =
  ## Inspect only the original final projection refusal.
  outcome.digestReason
proc authorizedInfo*(prepared: AuthorizedRefinement): AuthorizedRefinementResult[
    AuthorizedRefinementInfo] =
  ## Copy aggregate facts from a complete matching owner.
  let data = prepared.data
  if data == nil: return AuthorizedRefinementResult[AuthorizedRefinementInfo](
      status: AuthorizedRefinementError.Uninitialized)
  AuthorizedRefinementResult[AuthorizedRefinementInfo](status: AuthorizedRefinementError.None,
      completed: data.info)
proc authorizedSource*(prepared: AuthorizedRefinement): AuthorizedRefinementResult[
    AuthorizationInvocation] =
  ## Retain the original completed authorization owner and its exact complete state/package/parameter provenance.
  let data = prepared.data
  if data == nil: return AuthorizedRefinementResult[AuthorizationInvocation](
      status: AuthorizedRefinementError.Uninitialized)
  AuthorizedRefinementResult[AuthorizationInvocation](status: AuthorizedRefinementError.None,
      completed: data.authorization)
proc authorizedDigests*(prepared: AuthorizedRefinement): AuthorizedRefinementResult[
    RefinementDigests] =
  ## Retain the matching immutable digest projection, which itself owns its ordered report/export selection.
  let data = prepared.data
  if data == nil: return AuthorizedRefinementResult[RefinementDigests](
      status: AuthorizedRefinementError.Uninitialized)
  AuthorizedRefinementResult[RefinementDigests](status: AuthorizedRefinementError.None,
      completed: data.digests)

proc prepareAuthorizedRefinement*(authorization: AuthorizationInvocation, inputs: RefinementInputs,
    limits: AuthorizedRefinementLimits): AuthorizedRefinementResult[AuthorizedRefinement] =
  ## Select source identity and trace internally; borrowed input descriptions remain stable until this synchronous call returns.
  template fail(reason: AuthorizedRefinementError) =
    return AuthorizedRefinementResult[AuthorizedRefinement](status: reason)
  let selected = authorization.authorizationInfo
  if selected.error != AuthorizationInvocationError.None: fail(
      AuthorizedRefinementError.InvalidAuthorization)
  let auth = selected.value
  if auth.kind != WorkKind.Success:
    return AuthorizedRefinementResult[AuthorizedRefinement](
      status: AuthorizedRefinementError.AuthorizationRejected,
      authorizationReason: auth.kind) # A completed BAD/BIG/panic/OOG is not report-eligible successful authorization.
  if auth.traceBytes > 49152: fail(AuthorizedRefinementError.TraceTooLarge) # E's protocol gate precedes all trace copies/child policies.
  if auth.traceBytes > uint64(limits.trace): fail(AuthorizedRefinementError.LimitExceeded)
  let trace = authorization.authorizationTrace.value
  let refined = refinePackage(authorization.authorizationState.value,
    authorization.authorizationPackage.value,
    auth.core, authorization.authorizationParameters.value, trace, inputs, limits.refinement)
  if refined.error != RefinementReportError.None:
    return AuthorizedRefinementResult[AuthorizedRefinement](
      status: AuthorizedRefinementError.RefinementFailure,
      refinementReason: refined) # Retain only failed alternatives, never a completed partial report.
  let digests = prepareRefinementDigests(refined.value, limits.digests)
  if digests.error != RefinementDigestError.None:
    return AuthorizedRefinementResult[AuthorizedRefinement](
      status: AuthorizedRefinementError.DigestFailure,
      digestReason: digests.error) # Discard the private completed report on later local projection refusal.
  let info = refined.value.reportInfo.value
  AuthorizedRefinementResult[AuthorizedRefinement](status: AuthorizedRefinementError.None,
    completed: AuthorizedRefinement(data: AuthorizedData(authorization: authorization,
      digests: digests.value,
      info: AuthorizedRefinementInfo(core: auth.core, host: auth.host, anchor: auth.anchor,
        authorizationGasUsed: auth.gasUsed, traceBytes: auth.traceBytes, blobBytes: info.blobBytes,
        items: info.items, exports: info.exports))))
