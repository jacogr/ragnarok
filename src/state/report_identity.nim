# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Derive original package/authorizer identities and validate exact report lookup keys.
## Dictionary values remain unauthenticated; this immutable owner is not an availability certificate.

import ../codec/[bounded, composite, work_digest, work_package, work_report]
import ../crypto/primitives
import ./[authorized_refinement, authorization_invocation]

type
  ReportIdentityError* {.pure.} = enum ## Refusals contain no partial identity or lookup owner.
    Uninitialized, None, InvalidSource, InvalidLookup, NonCanonical, LimitExceeded,
    EncodingFailure, BackendFailure, InvalidIndex, MissingKey
  ReportIdentityLimits* = object ## Independent local hashing/copy caps include the complete respective preimages.
    packageBytes*, authorizerBytes*: ByteLimit
  ReportLookupIndex* = distinct uint64 ## Dictionary ordinal is separate from item and segment indices.
  ReportIdentityInfo* = object ## Copied report metadata remains tied to the original execution through the private owner.
    packageHash*: PackageHash
    authorizer*: AuthorizerHash
    context*: RefinementContext
    core*: CoreIndex
    authorizationGasUsed*: Gas
    lookupCount*: int
  IdentityData = ref object ## Acyclic immutable storage retains the original source and fixed copied dictionary.
    source: AuthorizedRefinement
    info: ReportIdentityInfo
    lookup: array[8, SegmentLookup]
  ReportIdentity* = object ## Only full preparation constructs an initialized source-bound handle.
    data: nil IdentityData
  ReportIdentityResult*[T] = object ## Private alternatives guard complete successful values in optimized builds.
    case status: ReportIdentityError
    of None:
      completed: T
    else:
      discard # Default/failure alternatives carry only their reason.

func error*[T](outcome: ReportIdentityResult[T]): ReportIdentityError =
  ## Inspect the reason without writable discriminator access.
  outcome.status
func value*[T](outcome: ReportIdentityResult[T]): T
    {.requires: outcome.status == ReportIdentityError.None.} =
  ## Extract only a fully selected successful value.
  outcome.completed
proc identityInfo*(identity: ReportIdentity): ReportIdentityResult[ReportIdentityInfo] =
  ## Copy fixed fields without exposing retained storage or detachable authority.
  let data = identity.data
  if data == nil: return ReportIdentityResult[ReportIdentityInfo](
      status: ReportIdentityError.Uninitialized)
  ReportIdentityResult[ReportIdentityInfo](status: ReportIdentityError.None, completed: data.info)
proc identitySource*(identity: ReportIdentity): ReportIdentityResult[AuthorizedRefinement] =
  ## Retain the exact matching authorization/refinement/digest provenance.
  let data = identity.data
  if data == nil: return ReportIdentityResult[AuthorizedRefinement](
      status: ReportIdentityError.Uninitialized)
  ReportIdentityResult[AuthorizedRefinement](status: ReportIdentityError.None,
      completed: data.source)
proc identityLookupAt*(identity: ReportIdentity, index: ReportLookupIndex): ReportIdentityResult[
    SegmentLookup] =
  ## Check full-width ordinals before narrowing into fixed private storage.
  let data = identity.data
  if data == nil: return ReportIdentityResult[SegmentLookup](
      status: ReportIdentityError.Uninitialized)
  if uint64(index) >= uint64(data.info.lookupCount):
    return ReportIdentityResult[SegmentLookup](status: ReportIdentityError.InvalidIndex)
  ReportIdentityResult[SegmentLookup](status: ReportIdentityError.None, completed: data.lookup[int(
      uint64(index))])
proc identityRoot*(identity: ReportIdentity, key: PackageHash): ReportIdentityResult[SegmentRoot] =
  ## Resolve only a validated dictionary key; success does not authenticate the associated commitment.
  let data = identity.data
  if data == nil: return ReportIdentityResult[SegmentRoot](
      status: ReportIdentityError.Uninitialized)
  # The complete dictionary has at most eight entries; extraction returns only copied fixed hashes.
  for index in 0..<data.info.lookupCount:
    # Equality selects an original supplied root without claiming proof verification.
    if data.lookup[index].packageHash.bytes == key.bytes:
      return ReportIdentityResult[SegmentRoot](status: ReportIdentityError.None,
          completed: data.lookup[index].segmentRoot)
  ReportIdentityResult[SegmentRoot](status: ReportIdentityError.MissingKey)
proc less(a, b: PackageHash): bool =
  ## Compare wire octets lexicographically without platform integer endianness.
  # Equality falls through; the first differing octet alone decides canonical order.
  for index in 0..<32:
    if a.bytes[index] != b.bytes[index]: return a.bytes[index] < b.bytes[index]
  false
proc prepareReportIdentity*(source: AuthorizedRefinement, lookup: openArray[SegmentLookup],
    limits: ReportIdentityLimits): ReportIdentityResult[ReportIdentity] =
  ## Borrow stable lookup pairs synchronously; derive every other field from the original execution owner.
  template fail(reason: ReportIdentityError) =
    return ReportIdentityResult[ReportIdentity](status: reason)
  let selected = source.authorizedInfo
  if selected.error != AuthorizedRefinementError.None: fail(ReportIdentityError.InvalidSource)
  let package = source.authorizedSource.value.authorizationPackage.value
  let info = package.workPackageInfo.value
  # Original captured context already proves prerequisiteCount in 0..8.
  if lookup.len > 8-info.context.prerequisiteCount: fail(ReportIdentityError.InvalidLookup)
  # Canonical wire dictionaries cannot contain duplicates or descending keys.
  for index in 1..<lookup.len:
    if not less(lookup[index-1].packageHash, lookup[index].packageHash):
      fail(ReportIdentityError.NonCanonical) # Never silently sort or collapse caller duplicates.
  var seen: array[8, bool] = default(array[8, bool])
  # Include every original manifest even when its refinement result is a protocol work error.
  for itemIndex in 0..<info.items:
    let item = package.workItemAt(itemIndex).value
    # Captured package metadata bounds each ordinal before owner-bound extraction.
    for importIndex in 0..<item.workItemInfo.value.imports:
      let reference = item.importAt(importIndex).value
      # Direct roots require no dictionary entry; only tagged package references contribute keys.
      if reference.kind == ImportKind.Package:
        var found = false
        # Repeated references reuse the same key; fixed seen storage has the preflighted lookup bound.
        for index in 0..<lookup.len:
          if lookup[index].packageHash.bytes == reference.package.bytes:
            seen[index] = true
            found = true # Repeated imports across items mark the same unique dictionary key.
        # A missing dependency rejects the complete candidate without hashing/copying.
        if not found: fail(ReportIdentityError.InvalidLookup)
  # Exact set equality rejects unused caller entries as well as missing imported keys.
  for index in 0..<lookup.len:
    if not seen[index]: fail(ReportIdentityError.InvalidLookup) # Extra keys fail even when all imports resolved.
  # Refuse all local work budgets before either preimage allocation.
  if uint64(info.consumed) > uint64(limits.packageBytes): fail(ReportIdentityError.LimitExceeded)
  # Prove the native allocation sum before adding the fixed code-hash prefix.
  if info.configurationBytes > high(int)-32: fail(ReportIdentityError.LimitExceeded)
  let authorizerSize = 32+info.configurationBytes
  if uint64(authorizerSize) > uint64(limits.authorizerBytes): fail(
      ReportIdentityError.LimitExceeded)
  var wire = newSeq[byte](info.consumed)
  if package.encodeOwnedWorkPackage(wire).error != PackageError.None: fail(
      ReportIdentityError.EncodingFailure)
  var authorizer = newSeq[byte](authorizerSize)
  let codeHash = array[32, byte](info.codeHash)
  for index in 0..<32: authorizer[index] = codeHash[
      index] # Hash identity precedes raw configuration without framing.
  # Empty configuration hashes exactly the code hash and needs no invalid empty span.
  if info.configurationBytes > 0:
    if package.copyPackageBlob(PackageBlob.Configuration, authorizer.toOpenArray(32,
        authorizer.high)).error != PackageError.None:
      fail(ReportIdentityError.EncodingFailure)
  let packageHash = blake2b256(wire)
  let authorizerHash = blake2b256(authorizer)
  if packageHash.error != CryptoError.None or authorizerHash.error != CryptoError.None:
    fail(ReportIdentityError.BackendFailure)
  var entries: array[8, SegmentLookup] = default(array[8, SegmentLookup])
  for index in 0..<lookup.len: entries[index] = lookup[index] # Fixed copied values cannot alias caller storage.
  ReportIdentityResult[ReportIdentity](status: ReportIdentityError.None,
    completed: ReportIdentity(data: IdentityData(source: source, lookup: entries,
      info: ReportIdentityInfo(packageHash: PackageHash(bytes: array[32, byte](packageHash.value)),
        authorizer: AuthorizerHash(bytes: array[32, byte](authorizerHash.value)),
        context: info.context, core: selected.value.core,
        authorizationGasUsed: selected.value.authorizationGasUsed, lookupCount: lookup.len))))
