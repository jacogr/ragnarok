# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 reporting_assurance.tex: parent authorizer membership, per-report gas and service
## code/minimum gas. This read-only stage consumes certified credentials; complete report
## context and C(10) publication follow later.
##
## Exposes unsigned reason-only inspection, credential-backed checkReportPolicy and immutable access to its certified credentials and parent
## snapshot.

import ../../codec/state/[authorization as state_authorization, accounts as state_accounts,
    layout as state_layout, safrole as state_safrole]
import ../../codec/[report_owned, owned, bounded]
import ../[store, guarantee_credentials]

type
  ReportGasLimit* = distinct uint64 ## Maximum accumulation gas for one report, distinct from per-item gas and the block-wide ceiling.
  RefinementGasLimit* = distinct uint64 ## Profile-bound package refinement ceiling is independent of accumulation gas.
  ReportPolicyConfig* = object ## Pool decode resources, fixed service metadata policy and explicit chain-specific report gas ceiling.
    pools*: AuthorizationConfig
    accountBytes*: ByteLimit
    reportGas*: ReportGasLimit
    refinementGas*: RefinementGasLimit
  ReportPolicyError* {.pure.} = enum ## Failed/default alternatives contain no checked reports, parent snapshot or partial gas totals.
    Uninitialized, None, InvalidConfig, InvalidCredentials, InvalidReport, InvalidState,
      MissingState,
    LimitExceeded, Unauthorized, UnknownService, WrongCodeHash, InsufficientGas, ReportGasExceeded, RefinementLoadExceeded
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

func validPolicyConfig(config: ReportPolicyConfig): bool =
  ## All callers use the same bounded core/account domains before any source copy or report traversal.
  uint64(config.pools.cores) >= 2 and uint64(config.pools.cores) <= 341 and
    uint64(config.accountBytes) >= uint64(ServiceMetadataBytes)

proc capturePolicyPools(parent: StateStoreSnapshot,
    config: ReportPolicyConfig): ReportPolicyResult[AuthorizationSnapshot] =
  ## Decode the exact bounded parent pool once; unsigned inspection grants no admission certificate.
  let entry = parent.lookup(chapterKey(StateChapter(1)))
  if entry.error == StateStoreError.MissingKey:
    return ReportPolicyResult[AuthorizationSnapshot](
        status: ReportPolicyError.MissingState) # Parent pool chapter must exist explicitly.
  if entry.error != StateStoreError.None:
    return ReportPolicyResult[AuthorizationSnapshot](
        status: ReportPolicyError.InvalidState) # Defaults are not complete parent maps.
  if uint64(entry.value.byteLength) > uint64(config.pools.maxBytes):
    return ReportPolicyResult[AuthorizationSnapshot](
        status: ReportPolicyError.LimitExceeded) # Check before copying an untrusted state value.
  let pools = decodeAuthorization(AuthorizationKind.Pools, entry.value.bytes, config.pools)
  if pools.error == AuthorizationError.LimitExceeded:
    return ReportPolicyResult[AuthorizationSnapshot](
        status: ReportPolicyError.LimitExceeded) # Preserve pool resource refusals.
  if pools.error != AuthorizationError.None:
    return ReportPolicyResult[AuthorizationSnapshot](
        status: ReportPolicyError.InvalidState) # No partially decoded pool is usable.
  if pools.value.consumed != entry.value.byteLength:
    return ReportPolicyResult[AuthorizationSnapshot](
        status: ReportPolicyError.InvalidState) # A chapter is an exact value, not a prefix.
  ReportPolicyResult[AuthorizationSnapshot](status: ReportPolicyError.None,
      completed: pools.value.snapshot)

proc inspectPolicyReport(report: OwnedReport, parent: StateStoreSnapshot,
    pools: AuthorizationSnapshot, config: ReportPolicyConfig): ReportPolicyError =
  ## Share every gas/service/code/pool rule between pre-signing inspection and certified report admission.
  let described = ownedReportInfo(report)
  if described.error != OwnershipError.None: return ReportPolicyError.InvalidReport
  let info = described.value
  let core = uint64(info.core)
  if core >= uint64(config.pools.cores):
    return ReportPolicyError.LimitExceeded # No core index outside this policy.
  let ordinal = AuthorizationCoreIndex(core)
  let hashes = authorizerCount(pools, ordinal).value
  var authorized = false
  # Search only this core's parent pool, preserving source order and repetitions.
  for j in 0..<hashes:
    let candidate = authorizerAt(pools, ordinal, AuthorizationIndex(j)).value
    if candidate.bytes == info.authorizer.bytes:
      authorized = true # Membership ignores pool ordering and preserves repeated entries.
      break
  if not authorized:
    return ReportPolicyError.Unauthorized # Parent C(1), never C(2) or a posterior pool.
  if uint64(info.authGas) > 50_000_000 or uint32(info.header.bundleLength) > 13_904_950:
    return ReportPolicyError.RefinementLoadExceeded # Independent fixed package authorization/bundle limits.
  var refineGas = 0'u64
  var imports = 0'u64
  var exports = 0'u64
  var extrinsics = 0'u64
  var inputBytes = 0'u64
  var total = 0'u64
  # Reset accumulation per report and validate every service, including unsuccessful work.
  for j in 0..<info.digestCount:
    let digest = ownedReportDigest(report, j).value
    let load = digest.refine
    if uint64(load.gasUsed) > uint64(config.refinementGas)-refineGas or
        uint64(load.imports) > 3072-imports or uint64(load.exports) > 3072-exports or
        uint64(load.extrinsicCount) > 128-extrinsics:
      return ReportPolicyError.RefinementLoadExceeded # Prove every aggregate before addition, including full-width counts.
    refineGas += uint64(load.gasUsed)
    imports += uint64(load.imports)
    exports += uint64(load.exports)
    extrinsics += uint64(load.extrinsicCount)
    let footprint = uint64(load.imports)*4488 # The3072 import bound proves this product fits uint64.
    if footprint > 13_791_360-inputBytes:
      return ReportPolicyError.RefinementLoadExceeded
    inputBytes += footprint
    if uint64(load.extrinsicSize) > 13_791_360-inputBytes:
      return ReportPolicyError.RefinementLoadExceeded # Work-report input excludes unavailable payload/configuration blobs.
    inputBytes += uint64(load.extrinsicSize)
    let amount = uint64(digest.accumulateGas)
    if amount > uint64(config.reportGas)-total:
      return ReportPolicyError.ReportGasExceeded # Check before adding, including full E8 overflow.
    total += amount
    let account = parent.lookup(chapterServiceKey(StateChapter(255), digest.service))
    if account.error == StateStoreError.MissingKey:
      return ReportPolicyError.UnknownService # No default account or guessed minimum.
    if account.error != StateStoreError.None:
      return ReportPolicyError.InvalidState # Invalid parent views cannot certify metadata.
    if account.value.byteLength != ServiceMetadataBytes:
      return ReportPolicyError.InvalidState # Exact fixed schema before allocating a byte copy.
    let metadata = decodeServiceMetadata(account.value.bytes, config.accountBytes)
    if metadata.error != ServiceMetadataError.None:
      return ReportPolicyError.InvalidState # Refuse invalid versions/metadata; no fallback.
    if array[32, byte](digest.codeHash) != array[32, byte](metadata.value.metadata.codeHash):
      return ReportPolicyError.WrongCodeHash # Predicted code belongs to this exact service.
    if amount < uint64(metadata.value.metadata.minimumAccumulationGas):
      return ReportPolicyError.InsufficientGas # Apply even to unsuccessful work outputs.
  if exports != uint64(info.header.segmentCount):
    return ReportPolicyError.RefinementLoadExceeded # Availability must commit exactly the declared exported segments.
  ReportPolicyError.None

proc inspectReportPolicy*(report: OwnedReport, parent: StateStoreSnapshot,
    config: ReportPolicyConfig): ReportPolicyError =
  ## Reason-only checks on one unsigned computed report cannot create credentials or a policy certificate.
  if not validPolicyConfig(config): return ReportPolicyError.InvalidConfig
  if ownedReportInfo(report).error != OwnershipError.None: return ReportPolicyError.InvalidReport
  let pools = capturePolicyPools(parent, config)
  if pools.error != ReportPolicyError.None: return pools.error
  inspectPolicyReport(report, parent, pools.value, config)

proc checkReportPolicy*(credentials: VerifiedGuaranteeCredentials, parent: StateStoreSnapshot,
    config: ReportPolicyConfig): ReportPolicyResult[PolicyCheckedReports] =
  ## Only genuine credentials can construct this certificate; all reports share one exact decoded parent pool.
  if not validPolicyConfig(config):
    return ReportPolicyResult[PolicyCheckedReports](status: ReportPolicyError.InvalidConfig)
  let count = credentials.verifiedGuaranteeCount
  if count.error != GuaranteeCredentialError.None:
    return ReportPolicyResult[PolicyCheckedReports](status: ReportPolicyError.InvalidCredentials)
  if uint64(count.value) > uint64(config.pools.cores):
    return ReportPolicyResult[PolicyCheckedReports](status: ReportPolicyError.LimitExceeded)
  let pools = capturePolicyPools(parent, config)
  if pools.error != ReportPolicyError.None:
    return ReportPolicyResult[PolicyCheckedReports](status: pools.error)
  for index in 0..<count.value:
    # A later refusal cannot expose an earlier successful prefix as a completed policy certificate.
    let report = credentials.verifiedGuaranteeAt(index).value.report
    let inspected = inspectPolicyReport(report, parent, pools.value, config)
    if inspected != ReportPolicyError.None:
      return ReportPolicyResult[PolicyCheckedReports](status: inspected)
  ReportPolicyResult[PolicyCheckedReports](status: ReportPolicyError.None,
    completed: PolicyCheckedReports(data: PolicyData(credentials: credentials, parent: parent)))
