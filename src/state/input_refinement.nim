# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute authorization/refinement from original verified inputs and retain their matching report identity.
## Root/state freshness and package-to-root correspondence remain explicit caller obligations.

import ../codec/bounded as codec_bounded
import ../codec/composite as codec_composite
import ../codec/work_package as codec_work_package
import ../codec/work_report as codec_work_report
import ../pvm/host_fetch as pvm_host_fetch
import ../chain/parameters as chain_parameters
import ./store as state_store
import ./import_inputs as state_import_inputs
import ./import_justification as state_import_justification
import ./extrinsic_inputs as state_extrinsic_inputs
import ./authorization_invocation as state_authorization_invocation
import ./authorized_refinement as state_authorized_refinement
import ./refinement_dispatch as state_refinement_dispatch
import ./report_identity as state_report_identity

type
  InputRefinementError* {.pure.} = enum ## Refusals retain only the selected reason, never a partial completed report.
    Uninitialized, None, InvalidInputs, LimitExceeded, AuthorizationFailure,
    AuthorizationRejected, TraceTooLarge, RefinementFailure, IdentityFailure
  InputRefinementLimits* = object ## Materialization policy supplements independent child execution/copy/hash limits.
    inputBytes*: ByteLimit
    authorization*: AuthorizationInvocationLimits
    refinement*: AuthorizedRefinementLimits
    identity*: ReportIdentityLimits
  InputRefinementData = ref object ## Acyclic immutable provenance binds original inputs to the identity derived after their execution.
    inputs: VerifiedImportInputs
    identity: ReportIdentity
  InputRefinement* = object ## Default handles contain no result, including no successful empty computation.
    data: nil InputRefinementData
  InputRefinementResult*[T] = object ## Private alternatives expose only complete success or the precise failed child.
    case status: InputRefinementError
    of None:
      completed: T
    of AuthorizationFailure:
      authorizationReason: AuthorizationInvocationResult[AuthorizationInvocation]
    of AuthorizationRejected:
      rejectedKind: WorkKind
    of RefinementFailure:
      refinementReason: AuthorizedRefinementResult[AuthorizedRefinement]
    of IdentityFailure:
      identityReason: ReportIdentityError
    else:
      discard # Simple local/protocol refusals have no source, output or unrelated child detail.

func error*[T](outcome: InputRefinementResult[T]): InputRefinementError =
  ## Inspect the reason without a writable discriminator.
  outcome.status
func value*[T](outcome: InputRefinementResult[T]): T
    {.requires: outcome.status == InputRefinementError.None.} =
  ## Extract only the complete successful owner.
  outcome.completed
func authorizationError*[T](outcome: InputRefinementResult[T]): AuthorizationInvocationResult[AuthorizationInvocation]
    {.requires: outcome.status == InputRefinementError.AuthorizationFailure.} =
  ## Preserve the original failed authorization alternative and its guarded stage details.
  outcome.authorizationReason
func authorizationKind*[T](outcome: InputRefinementResult[T]): WorkKind
    {.requires: outcome.status == InputRefinementError.AuthorizationRejected.} =
  ## Inspect only a genuine completed authorization's protocol work error.
  outcome.rejectedKind
func refinementError*[T](outcome: InputRefinementResult[T]): AuthorizedRefinementResult[AuthorizedRefinement]
    {.requires: outcome.status == InputRefinementError.RefinementFailure.} =
  ## Preserve the exact failed refinement/digest alternative, never a completed prefix.
  outcome.refinementReason
func identityError*[T](outcome: InputRefinementResult[T]): ReportIdentityError
    {.requires: outcome.status == InputRefinementError.IdentityFailure.} =
  ## Inspect only final identity derivation's refusal.
  outcome.identityReason
proc inputRefinementSource*(completed: InputRefinement): InputRefinementResult[
    VerifiedImportInputs] =
  ## Retain the exact input owner used before authorization and guest execution.
  let data = completed.data
  if data == nil: return InputRefinementResult[VerifiedImportInputs](
      status: InputRefinementError.Uninitialized)
  InputRefinementResult[VerifiedImportInputs](status: InputRefinementError.None,
      completed: data.inputs)
proc inputRefinementIdentity*(completed: InputRefinement): InputRefinementResult[ReportIdentity] =
  ## Retain only the identity derived from this owner's executed package and original lookup dictionary.
  let data = completed.data
  if data == nil: return InputRefinementResult[ReportIdentity](
      status: InputRefinementError.Uninitialized)
  InputRefinementResult[ReportIdentity](status: InputRefinementError.None, completed: data.identity)
proc runInputRefinement*(state: StateStoreSnapshot, inputs: VerifiedImportInputs, core: CoreIndex,
    parameters: Parameters, limits: InputRefinementLimits): InputRefinementResult[InputRefinement] =
  ## Execute synchronously from immutable original sources; no detached execution artifact can be attached afterward.
  template fail(reason: InputRefinementError) =
    return InputRefinementResult[InputRefinement](status: reason)
  let described = inputs.importInputsInfo
  if described.error != ImportInputsError.None: fail(InputRefinementError.InvalidInputs)
  let extrinsics = inputs.importInputsExtrinsics.value
  let package = extrinsics.extrinsicInputsPackage.value
  let authorized = runAuthorizationInvocation(state, package, core, parameters,
      limits.authorization)
  if authorized.error != AuthorizationInvocationError.None:
    return InputRefinementResult[InputRefinement](status: InputRefinementError.AuthorizationFailure,
      authorizationReason: authorized) # The stored child is a failed alternative without a partial invocation.
  let authInfo = authorized.value.authorizationInfo.value
  if authInfo.kind != WorkKind.Success:
    return InputRefinementResult[InputRefinement](
      status: InputRefinementError.AuthorizationRejected,
      rejectedKind: authInfo.kind) # Protocol rejection precedes materialization and all refinement policies.
  if authInfo.traceBytes > 49152: fail(InputRefinementError.TraceTooLarge)
  if authInfo.traceBytes > uint64(limits.refinement.trace): fail(InputRefinementError.LimitExceeded)
  let extrinsicBytes = extrinsics.extrinsicInputsInfo.value.payloadBytes
  let importBytes = uint64(described.value.entries)*4104 # The verified manifest bounds entries to 3072 before multiplication.
  if extrinsicBytes > uint64(limits.inputBytes): fail(InputRefinementError.LimitExceeded)
  if importBytes > uint64(limits.inputBytes)-extrinsicBytes: fail(
      InputRefinementError.LimitExceeded)
  let count = described.value.items
  var materialized = RefinementInputs(extrinsics: newSeq[seq[seq[byte]]](count),
    imports: newSeq[seq[FetchSegment]](count))
  # Immutable manifest/table matching proves every ordinal before extraction; no caller replacement bytes are accepted.
  for item in 0..<count:
    let selected = package.workItemAt(item).value.workItemInfo.value
    materialized.extrinsics[item] = newSeq[seq[byte]](selected.extrinsics)
    for index in 0..<selected.extrinsics:
      materialized.extrinsics[item][index] = extrinsics.extrinsicInput(FetchItemIndex(uint64(item)),
        ExtrinsicInputIndex(uint64(index))).value
    materialized.imports[item] = newSeq[FetchSegment](selected.imports)
    for index in 0..<selected.imports:
      materialized.imports[item][index] = inputs.importInput(FetchItemIndex(uint64(item)),
        ImportInputIndex(uint64(index))).value.verifiedImportSegment.value
  let refined = prepareAuthorizedRefinement(authorized.value, materialized, limits.refinement)
  if refined.error != AuthorizedRefinementError.None:
    return InputRefinementResult[InputRefinement](status: InputRefinementError.RefinementFailure,
      refinementReason: refined) # Late local failure cannot expose earlier successful item output.
  let identity = prepareReportIdentity(refined.value, inputs.importInputsLookup.value,
      limits.identity)
  if identity.error != ReportIdentityError.None:
    return InputRefinementResult[InputRefinement](status: InputRefinementError.IdentityFailure,
      identityReason: identity.error) # Discard private completed execution when final identity projection fails.
  InputRefinementResult[InputRefinement](status: InputRefinementError.None,
    completed: InputRefinement(data: InputRefinementData(inputs: inputs, identity: identity.value)))
