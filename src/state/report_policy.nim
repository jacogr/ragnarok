# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 reporting_assurance.tex: parent authorizer membership, per-report gas and service
## code/minimum gas. This read-only stage consumes certified credentials; complete report
## context and C(10) publication follow later.
##
## Exposes checkReportPolicy and immutable access to its certified credentials and parent
## snapshot.

import ../codec/state_authorization as codec_state_authorization
import ../codec/state_accounts as codec_state_accounts
import ../codec/state_layout as codec_state_layout
import ../codec/state_safrole as codec_state_safrole
import ../codec/report_owned as codec_report_owned
import ../codec/owned as codec_owned
import ../codec/bounded as codec_bounded
import ./store as state_store
import ./guarantee_credentials as state_guarantee_credentials

type
  ReportGasLimit* = distinct uint64 ## Maximum accumulation gas for one report, distinct from per-item gas and the block-wide ceiling.
  ReportPolicyConfig* = object ## Pool decode resources, fixed service metadata policy and explicit chain-specific report gas ceiling.
    pools*: AuthorizationConfig
    accountBytes*: ByteLimit
    reportGas*: ReportGasLimit
  ReportPolicyError* {.pure.} = enum ## Failed/default alternatives contain no checked reports, parent snapshot or partial gas totals.
    Uninitialized, None, InvalidConfig, InvalidCredentials, InvalidState, MissingState,
    LimitExceeded, Unauthorized, UnknownService, WrongCodeHash, InsufficientGas, ReportGasExceeded
  ## Private acyclic owner binds the credential certificate to the exact immutable parent map used for policy.
  PolicyData = ref object
    credentials: VerifiedGuaranteeCredentials
    parent: StateStoreSnapshot
  PolicyCheckedReports* = object ## A completed policy certificate is still not a complete report-admission or state-transition certificate.
    data: nil PolicyData
  ReportPolicyResult*[T] = object ## Only complete success carries an application value; failed alternatives carry a reason alone.
    case status: ReportPolicyError
    of None:
      completed: T
    else:
      discard # Defaults and refusals cannot expose checked records or progress.

func error*[T](outcome: ReportPolicyResult[T]): ReportPolicyError =
  ## Inspect status without permitting external retagging.
  outcome.status
func value*[T](outcome: ReportPolicyResult[T]): T {.inline,
    requires: outcome.status == ReportPolicyError.None.} =
  ## Extract only selected success under the supported checked-build contract.
  outcome.completed

proc policyCredentials*(owner: PolicyCheckedReports): ReportPolicyResult[
    VerifiedGuaranteeCredentials] =
  ## Retain the exact certified credentials, with their immutable records and reporter keys.
  let data = owner.data
  if data == nil:
    return ReportPolicyResult[VerifiedGuaranteeCredentials](
        status: ReportPolicyError.Uninitialized) # No fabricated empty batch.
  ReportPolicyResult[VerifiedGuaranteeCredentials](status: ReportPolicyError.None,
      completed: data.credentials)

proc policyParent*(owner: PolicyCheckedReports): ReportPolicyResult[StateStoreSnapshot] =
  ## Retain the complete parent map actually used, so later admission cannot silently substitute another buffer/state.
  let data = owner.data
  if data == nil:
    return ReportPolicyResult[StateStoreSnapshot](
        status: ReportPolicyError.Uninitialized) # No default parent certificate.
  ReportPolicyResult[StateStoreSnapshot](status: ReportPolicyError.None, completed: data.parent)

proc checkReportPolicy*(credentials: VerifiedGuaranteeCredentials, parent: StateStoreSnapshot,
    config: ReportPolicyConfig): ReportPolicyResult[PolicyCheckedReports] =
  ## Read parent C(1) and C(255,service) only; no pool advancement, state mutation, hashing or PVM execution occurs.
  ## The caller supplies the actual admitted parent and matching completed credential context, authenticated externally.
  if uint64(config.pools.cores) < 2 or uint64(config.pools.cores) > 341 or
      uint64(config.accountBytes) < uint64(ServiceMetadataBytes):
    return ReportPolicyResult[PolicyCheckedReports](
        status: ReportPolicyError.InvalidConfig) # Bound domains before traversal/copy.
  let count = credentials.verifiedGuaranteeCount
  if count.error != GuaranteeCredentialError.None:
    return ReportPolicyResult[PolicyCheckedReports](
        status: ReportPolicyError.InvalidCredentials) # No raw or default batch.
  if uint64(count.value) > uint64(config.pools.cores):
    return ReportPolicyResult[PolicyCheckedReports](
        status: ReportPolicyError.LimitExceeded) # Recheck a certificate made under looser policy.
  let entry = parent.lookup(chapterKey(StateChapter(1)))
  if entry.error == StateStoreError.MissingKey:
    return ReportPolicyResult[PolicyCheckedReports](
        status: ReportPolicyError.MissingState) # Parent pool chapter must exist explicitly.
  if entry.error != StateStoreError.None:
    return ReportPolicyResult[PolicyCheckedReports](
        status: ReportPolicyError.InvalidState) # Defaults are not complete parent maps.
  if uint64(entry.value.byteLength) > uint64(config.pools.maxBytes):
    return ReportPolicyResult[PolicyCheckedReports](
        status: ReportPolicyError.LimitExceeded) # Check before copying an untrusted state value.
  let pools = decodeAuthorization(AuthorizationKind.Pools, entry.value.bytes, config.pools)
  if pools.error == AuthorizationError.LimitExceeded:
    return ReportPolicyResult[PolicyCheckedReports](
        status: ReportPolicyError.LimitExceeded) # Preserve pool resource refusals.
  if pools.error != AuthorizationError.None:
    return ReportPolicyResult[PolicyCheckedReports](
        status: ReportPolicyError.InvalidState) # No partially decoded pool is usable.
  if pools.value.consumed != entry.value.byteLength:
    return ReportPolicyResult[PolicyCheckedReports](
        status: ReportPolicyError.InvalidState) # A chapter is an exact value, not a prefix.
  # Every report must pass; no partial earlier batch is exposed.
  for i in 0..<count.value:
    let record = credentials.verifiedGuaranteeAt(i).value
    let info = ownedReportInfo(record.report).value
    let core = uint64(info.core)
    if core >= uint64(config.pools.cores):
      return ReportPolicyResult[PolicyCheckedReports](
          status: ReportPolicyError.LimitExceeded) # No core index outside this policy.
    let ordinal = AuthorizationCoreIndex(core)
    let hashes = authorizerCount(pools.value.snapshot, ordinal).value
    var authorized = false
    # Search only this core's parent pool, preserving source order and repetitions.
    for j in 0..<hashes:
      let candidate = authorizerAt(pools.value.snapshot, ordinal, AuthorizationIndex(j)).value
      if candidate.bytes == info.authorizer.bytes:
        authorized = true # Membership ignores pool ordering and preserves repeated entries.
        break
    if not authorized:
      return ReportPolicyResult[PolicyCheckedReports](
          status: ReportPolicyError.Unauthorized) # Parent C(1), never C(2) or a posterior pool.
    var total = 0'u64
    # Reset accumulation per report and validate every service, including unsuccessful work.
    for j in 0..<info.digestCount:
      let digest = ownedReportDigest(record.report, j).value
      let amount = uint64(digest.accumulateGas)
      if amount > uint64(config.reportGas)-total:
        return ReportPolicyResult[PolicyCheckedReports](
            status: ReportPolicyError.ReportGasExceeded) # Check before adding, including full E8 overflow.
      total += amount
      let account = parent.lookup(chapterServiceKey(StateChapter(255), digest.service))
      if account.error == StateStoreError.MissingKey:
        return ReportPolicyResult[PolicyCheckedReports](
            status: ReportPolicyError.UnknownService) # No default account or guessed minimum.
      if account.error != StateStoreError.None:
        return ReportPolicyResult[PolicyCheckedReports](
            status: ReportPolicyError.InvalidState) # Invalid parent views cannot certify metadata.
      if account.value.byteLength != ServiceMetadataBytes:
        return ReportPolicyResult[PolicyCheckedReports](
            status: ReportPolicyError.InvalidState) # Exact fixed schema before allocating a byte copy.
      let metadata = decodeServiceMetadata(account.value.bytes, config.accountBytes)
      if metadata.error != ServiceMetadataError.None:
        return ReportPolicyResult[PolicyCheckedReports](
            status: ReportPolicyError.InvalidState) # Refuse invalid versions/metadata; no fallback.
      if array[32, byte](digest.codeHash) != array[32, byte](metadata.value.metadata.codeHash):
        return ReportPolicyResult[PolicyCheckedReports](
            status: ReportPolicyError.WrongCodeHash) # Predicted code belongs to this exact service.
      if amount < uint64(metadata.value.metadata.minimumAccumulationGas):
        return ReportPolicyResult[PolicyCheckedReports](
            status: ReportPolicyError.InsufficientGas) # Apply even to unsuccessful work outputs.
  ReportPolicyResult[PolicyCheckedReports](status: ReportPolicyError.None,
    completed: PolicyCheckedReports(data: PolicyData(credentials: credentials, parent: parent)))
