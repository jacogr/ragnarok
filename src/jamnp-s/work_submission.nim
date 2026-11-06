# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authorize bounded CE133/146 headers before authenticating original package-bound body inputs.
## Synchronous complete-state owners belong behind the application's managed graph gate, never in callbacks.
import ../codec/[bounded, natural, composite, assurances]
import ../codec/work/[package as work_package, report as work_report]
import ../codec/state/[authorization as state_authorization, history as state_history,
    layout as state_layout]
import ../chain/parameters
import ../crypto/primitives
import ../pvm/host/fetch as host_fetch
import ../state/[store, extrinsic_inputs]
import ../state/authorization/invocation as authorization_invocation
import "../state/import/inputs" as import_inputs
import "../state/import/justification" as import_justification

type
  WorkSubmissionKind* {.pure.} = enum ## The forms have different message boundaries and import acquisition contracts.
    Package, Bundle
  WorkSubmissionError* {.pure.} = enum ## Defaults and refusals carry no header, grant or authenticated prefix.
    Uninitialized, None, InvalidMessage, LimitExceeded, InvalidPolicy, InvalidSource,
    PackageFailure, InvalidMappings, UnavailableMapping, Unauthorized, BackendFailure,
    AuthorizationFailure, AuthorizationRejected, ExtrinsicFailure, ImportFailure, BindingFailure
  WorkSubmissionLimits* = object ## Independent child ceilings remain explicit; no network input selects a policy.
    pools*: AuthorizationConfig
    history*: HistoryConfig
    authorization*: AuthorizationInvocationLimits
    extrinsics*: ExtrinsicInputsLimits
    imports*: ImportInputsLimits
    proof*: ImportJustificationLimits
  WorkSubmissionInfo* = object ## Detached geometry tells a staged reader what to charge before copying any large body.
    kind*: WorkSubmissionKind
    core*: CoreIndex
    packageBytes*, extrinsicBytes*, segmentBytes*, importCount*, mappingCount*: int
  HeaderData = ref object ## Private immutable original package and fixed dictionary retain no borrowed wire buffers.
    package: OwnedWorkPackage
    info: WorkSubmissionInfo
    lookup: array[8, SegmentLookup]
  WorkSubmissionHeader* = object ## Structural decoding alone supplies no body-read or execution authority.
    data: nil HeaderData
  GrantData = ref object ## An acyclic grant binds the exact header to real successful authorization and its original state.
    header: HeaderData
    authorization: AuthorizationInvocation
  AuthorizedWorkSubmission* = object ## Only actual pool membership and successful guest execution can construct this handle.
    data: nil GrantData
  WorkSubmissionResult*[T] = object ## Guarded children preserve genuine stage causes, without retagging partial results.
    case status: WorkSubmissionError
    of None: completed: T
    of PackageFailure: packageReason: PackageError
    of AuthorizationFailure: authorizationReason: AuthorizationInvocationResult[AuthorizationInvocation]
    of AuthorizationRejected: rejectedKind: WorkKind
    of ExtrinsicFailure: extrinsicReason: ExtrinsicInputsError
    of ImportFailure: importReason: ImportJustificationError
    of BindingFailure: bindingReason: ImportInputsError
    else: discard # Simple refusals contain only their reason.

func error*[T](outcome: WorkSubmissionResult[T]): WorkSubmissionError =
  ## Inspect a result without exposing a writable discriminator.
  outcome.status
func value*[T](outcome: WorkSubmissionResult[T]): T {.requires: outcome.status ==
    WorkSubmissionError.None.} =
  ## Extract only completely selected success.
  outcome.completed
func packageError*[T](outcome: WorkSubmissionResult[T]): PackageError {.requires: outcome.status ==
    WorkSubmissionError.PackageFailure.} =
  ## Preserve the original canonical package decoder's refusal.
  outcome.packageReason
func authorizationError*[T](outcome: WorkSubmissionResult[T]): AuthorizationInvocationResult[
    AuthorizationInvocation] {.requires: outcome.status ==
    WorkSubmissionError.AuthorizationFailure.} =
  ## Retain the genuine failed child, including its guarded nested cause.
  outcome.authorizationReason
func authorizationKind*[T](outcome: WorkSubmissionResult[T]): WorkKind {.requires: outcome.status ==
    WorkSubmissionError.AuthorizationRejected.} =
  ## Expose the actual completed guest work error only on rejection.
  outcome.rejectedKind
func extrinsicError*[T](outcome: WorkSubmissionResult[
    T]): ExtrinsicInputsError {.requires: outcome.status == WorkSubmissionError.ExtrinsicFailure.} =
  ## Hash/length/backend failures remain distinct from framing failures.
  outcome.extrinsicReason
func importError*[T](outcome: WorkSubmissionResult[
    T]): ImportJustificationError {.requires: outcome.status ==
    WorkSubmissionError.ImportFailure.} =
  ## Preserve the selected segment proof verifier's cause.
  outcome.importReason
func bindingError*[T](outcome: WorkSubmissionResult[
    T]): ImportInputsError {.requires: outcome.status == WorkSubmissionError.BindingFailure.} =
  ## A complete table mismatch never exposes its earlier verified rows.
  outcome.bindingReason
proc submissionInfo*(header: WorkSubmissionHeader): WorkSubmissionResult[WorkSubmissionInfo] =
  ## Copy bounded geometry without granting authority to read a body.
  let data = header.data
  if data == nil: return WorkSubmissionResult[WorkSubmissionInfo](
      status: WorkSubmissionError.Uninitialized)
  WorkSubmissionResult[WorkSubmissionInfo](status: WorkSubmissionError.None, completed: data.info)
proc submissionInfo*(grant: AuthorizedWorkSubmission): WorkSubmissionResult[WorkSubmissionInfo] =
  ## Only a genuine grant exposes authorized reader geometry.
  let data = grant.data
  if data == nil: return WorkSubmissionResult[WorkSubmissionInfo](
      status: WorkSubmissionError.Uninitialized)
  WorkSubmissionResult[WorkSubmissionInfo](status: WorkSubmissionError.None,
      completed: data.header.info)
func less(a, b: PackageHash): bool =
  ## Canonical dictionary order compares full wire octets, independently of host endianness.
  for index in 0..<32:
    if a.bytes[index] != b.bytes[index]: return a.bytes[index] < b.bytes[index]
  false
proc dictionary(payload: openArray[byte]): WorkSubmissionResult[seq[SegmentLookup]] =
  ## Preflight the complete count/extent before allocating at most eight fixed records.
  let count = decode(payload)
  if not count.ok: return WorkSubmissionResult[seq[SegmentLookup]](
      status: WorkSubmissionError.InvalidMappings)
  if uint64(count.value) > 8: return WorkSubmissionResult[seq[SegmentLookup]](
      status: WorkSubmissionError.LimitExceeded)
  let size = int(uint64(count.value))
  if payload.len-count.consumed != size*64: return WorkSubmissionResult[seq[SegmentLookup]](
      status: WorkSubmissionError.InvalidMappings)
  var rows = newSeq[SegmentLookup](size)
  for index in 0..<size:
    # Exact bounded extent proves all accesses; no caller-owned descriptor is retained.
    let start = count.consumed+index*64
    for octet in 0..<32:
      rows[index].packageHash.bytes[octet] = payload[start+octet]
      rows[index].segmentRoot.bytes[octet] = payload[start+32+octet]
    if index > 0:
      if not less(rows[index-1].packageHash, rows[index].packageHash):
        return WorkSubmissionResult[seq[SegmentLookup]](status: WorkSubmissionError.InvalidMappings)
  WorkSubmissionResult[seq[SegmentLookup]](status: WorkSubmissionError.None, completed: rows)
proc decodeWorkSubmission*(kind: WorkSubmissionKind, first, packageMessage: openArray[byte],
    config: PackageConfig): WorkSubmissionResult[WorkSubmissionHeader] =
  ## Decode exact CE133/146 header payloads; outer E4 framing belongs to the staged transport reader.
  template fail(reason: WorkSubmissionError) =
    return WorkSubmissionResult[WorkSubmissionHeader](status: reason)
  if ord(kind) > ord(WorkSubmissionKind.Bundle): fail(WorkSubmissionError.InvalidMessage)
  if first.len < 2: fail(WorkSubmissionError.InvalidMessage)
  let core = CoreIndex(uint64(first[0]) or (uint64(first[1]) shl 8))
  var package = default(OwnedWorkPackage)
  var mappings: seq[SegmentLookup] = @[]
  if kind == WorkSubmissionKind.Package:
    # CE133 has a single small header containing core and package, with no second header message.
    if first.len > 204802: fail(WorkSubmissionError.LimitExceeded)
    if first.len == 2 or packageMessage.len != 0: fail(WorkSubmissionError.InvalidMessage)
    let decoded = decodeWorkPackage(first.toOpenArray(2, first.high), config)
    if decoded.error != PackageError.None: return WorkSubmissionResult[WorkSubmissionHeader](
        status: WorkSubmissionError.PackageFailure, packageReason: decoded.error)
    if decoded.value.consumed != first.len-2: fail(WorkSubmissionError.InvalidMessage)
    package = decoded.value.owner
  else:
    # CE146 mappings are independently bounded before any package decoding or authorization.
    if first.len > 515: fail(WorkSubmissionError.LimitExceeded)
    if first.len == 2: fail(WorkSubmissionError.InvalidMappings)
    let decodedMappings = dictionary(first.toOpenArray(2, first.high))
    if decodedMappings.error != WorkSubmissionError.None: fail(decodedMappings.error)
    mappings = decodedMappings.value
    if packageMessage.len > 204800: fail(WorkSubmissionError.LimitExceeded)
    if packageMessage.len == 0: fail(WorkSubmissionError.InvalidMessage)
    let decoded = decodeWorkPackage(packageMessage, config)
    if decoded.error != PackageError.None: return WorkSubmissionResult[WorkSubmissionHeader](
        status: WorkSubmissionError.PackageFailure, packageReason: decoded.error)
    if decoded.value.consumed != packageMessage.len: fail(WorkSubmissionError.InvalidMessage)
    package = decoded.value.owner
  let described = package.workPackageInfo.value
  var info = WorkSubmissionInfo(kind: kind, core: core, packageBytes: described.consumed,
      mappingCount: mappings.len)
  var lookup = default(array[8, SegmentLookup])
  var seen = default(array[8, bool])
  if mappings.len > 8-described.context.prerequisiteCount: fail(WorkSubmissionError.InvalidMappings)
  for index in 0..<mappings.len: lookup[index] = mappings[index] # Fixed values cannot alias input storage.
  for item in 0..<described.items:
    # Package decoding has already proved the 16-item, 128-extrinsic and 3072-import domains.
    let selected = package.workItemAt(item).value
    let itemInfo = selected.workItemInfo.value
    for index in 0..<itemInfo.extrinsics:
      let length = uint64(uint32(selected.extrinsicAt(index).value.length))
      if length > 13904950'u64-uint64(info.extrinsicBytes): fail(WorkSubmissionError.LimitExceeded)
      info.extrinsicBytes += int(length)
    for index in 0..<itemInfo.imports:
      inc info.importCount
      let reference = selected.importAt(index).value
      if kind == WorkSubmissionKind.Bundle and reference.kind == ImportKind.Package:
        var found = false
        for key in 0..<mappings.len:
          if mappings[key].packageHash.bytes == reference.package.bytes:
            seen[key] = true
            found = true
        if not found: fail(WorkSubmissionError.InvalidMappings)
  for index in 0..<mappings.len:
    if not seen[index]: fail(WorkSubmissionError.InvalidMappings) # Unrelated dictionary entries cannot inflate authority.
  info.segmentBytes = info.importCount*4104 # The validated manifest proves multiplication and native allocation extent.
  if info.packageBytes+info.extrinsicBytes+info.segmentBytes+info.importCount > 13904950:
    fail(WorkSubmissionError.LimitExceeded) # Even empty proof paths require one canonical count byte per imported leaf.
  WorkSubmissionResult[WorkSubmissionHeader](status: WorkSubmissionError.None,
    completed: WorkSubmissionHeader(data: HeaderData(package: package, info: info, lookup: lookup)))
proc checkMappings(state: StateStoreSnapshot, lookup: openArray[SegmentLookup],
    config: HistoryConfig): WorkSubmissionError =
  ## Accept only mappings visible in this exact source's bounded recent history; never trust peer-supplied roots.
  if lookup.len == 0: return WorkSubmissionError.None
  let entry = state.lookup(chapterKey(StateChapter(3)))
  if entry.error != StateStoreError.None: return WorkSubmissionError.InvalidSource
  if uint64(entry.value.byteLength) > uint64(config.maxBytes): return WorkSubmissionError.LimitExceeded
  let history = decodeHistoryState(entry.value.bytes, config)
  if history.error != HistoryError.None: return WorkSubmissionError.InvalidSource
  if history.value.consumed != entry.value.byteLength: return WorkSubmissionError.InvalidSource
  let owner = history.value.snapshot
  for pair in lookup:
    # Bounded C(3) has at most eight blocks; policy also charges total package pairs before capture.
    var found = false
    for blockIndex in 0..<owner.historyInfo.value.blocks:
      for index in 0..<owner.historyBlockAt(HistoryBlockIndex(blockIndex)).value.packages:
        let candidate = owner.historyPackageAt(HistoryBlockIndex(blockIndex), HistoryPackageIndex(index)).value
        if candidate.package.bytes == pair.packageHash.bytes and candidate.segment.bytes ==
            pair.segmentRoot.bytes: found = true
    if not found: return WorkSubmissionError.UnavailableMapping
  WorkSubmissionError.None
proc authorizeWorkSubmission*(header: WorkSubmissionHeader, state: StateStoreSnapshot,
    parameters: Parameters, limits: WorkSubmissionLimits): WorkSubmissionResult[
        AuthorizedWorkSubmission] =
  ## Read only the original source's selected pool and execute its historical authorizer before granting body access.
  template fail(reason: WorkSubmissionError) =
    return WorkSubmissionResult[AuthorizedWorkSubmission](status: reason)
  let data = header.data
  if data == nil: fail(WorkSubmissionError.Uninitialized)
  if not parameters.valid: fail(WorkSubmissionError.InvalidPolicy)
  let cores = parameters.get(coreCount)
  if cores < 2 or cores > 341 or uint64(limits.pools.cores) != cores or uint64(
      limits.history.cores) != cores: fail(WorkSubmissionError.InvalidPolicy)
  if uint64(data.info.core) >= cores: fail(WorkSubmissionError.InvalidMessage)
  let entry = state.lookup(chapterKey(StateChapter(1)))
  if entry.error != StateStoreError.None: fail(WorkSubmissionError.InvalidSource)
  if uint64(entry.value.byteLength) > uint64(limits.pools.maxBytes): fail(
      WorkSubmissionError.LimitExceeded)
  let pools = decodeAuthorization(AuthorizationKind.Pools, entry.value.bytes, limits.pools)
  if pools.error != AuthorizationError.None: fail(WorkSubmissionError.InvalidSource)
  if pools.value.consumed != entry.value.byteLength: fail(WorkSubmissionError.InvalidSource)
  let packageInfo = data.package.workPackageInfo.value
  var preimage = newSeq[byte](32+packageInfo.configurationBytes) # Package is capped at 200 KiB before this bounded copy.
  let code = array[32, byte](packageInfo.codeHash)
  for index in 0..<32: preimage[index] = code[index]
  if packageInfo.configurationBytes > 0:
    # The encoding owner proves the exact configuration span after the fixed code hash.
    if data.package.copyPackageBlob(PackageBlob.Configuration, preimage.toOpenArray(32,
        preimage.high)).error != PackageError.None: fail(WorkSubmissionError.InvalidSource)
  let hashed = blake2b256(preimage)
  if hashed.error != CryptoError.None: fail(WorkSubmissionError.BackendFailure)
  let ordinal = AuthorizationCoreIndex(uint64(data.info.core))
  var present = false
  for index in 0..<pools.value.snapshot.authorizerCount(ordinal).value:
    if pools.value.snapshot.authorizerAt(ordinal, AuthorizationIndex(index)).value.bytes == array[
        32, byte](hashed.value): present = true
  if not present: fail(WorkSubmissionError.Unauthorized)
  if data.info.mappingCount > 0:
    # Dictionary membership is checked before expensive guest work or large body acquisition.
    let mapped = checkMappings(state, data.lookup.toOpenArray(0, data.info.mappingCount-1),
        limits.history)
    if mapped != WorkSubmissionError.None: fail(mapped)
  let authorized = runAuthorizationInvocation(state, data.package, data.info.core, parameters,
      limits.authorization)
  if authorized.error != AuthorizationInvocationError.None: return WorkSubmissionResult[
      AuthorizedWorkSubmission](status: WorkSubmissionError.AuthorizationFailure,
      authorizationReason: authorized)
  let info = authorized.value.authorizationInfo.value
  if info.kind != WorkKind.Success: return WorkSubmissionResult[AuthorizedWorkSubmission](
      status: WorkSubmissionError.AuthorizationRejected, rejectedKind: info.kind)
  if info.traceBytes > 49152: fail(WorkSubmissionError.LimitExceeded)
  WorkSubmissionResult[AuthorizedWorkSubmission](status: WorkSubmissionError.None,
    completed: AuthorizedWorkSubmission(data: GrantData(header: data,
        authorization: authorized.value)))
proc verifiedExtrinsics(grant: AuthorizedWorkSubmission, payload: openArray[byte],
    limits: ExtrinsicInputsLimits): WorkSubmissionResult[VerifiedExtrinsics] =
  ## Exact expected length and policy checks precede nested table allocations and hashing.
  template fail(reason: WorkSubmissionError) =
    return WorkSubmissionResult[VerifiedExtrinsics](status: reason)
  let granted = grant.data
  if granted == nil: fail(WorkSubmissionError.Uninitialized)
  let data = granted.header
  if payload.len != data.info.extrinsicBytes: fail(WorkSubmissionError.InvalidMessage)
  if uint64(payload.len) > uint64(limits.payloadBytes): fail(WorkSubmissionError.LimitExceeded)
  if uint64(payload.len) > uint64(limits.hashBytes): fail(WorkSubmissionError.LimitExceeded)
  let count = data.package.workPackageInfo.value.items
  var entries = 0
  for item in 0..<count: entries += data.package.workItemAt(
      item).value.workItemInfo.value.extrinsics
  if uint64(entries) > uint64(limits.entries): fail(WorkSubmissionError.LimitExceeded)
  var rows = newSeq[seq[seq[byte]]](count)
  var cursor = 0
  for item in 0..<count:
    # Original commitment lengths exactly partition the preflighted payload, including empty occurrences.
    let selected = data.package.workItemAt(item).value
    rows[item] = newSeq[seq[byte]](selected.workItemInfo.value.extrinsics)
    for index in 0..<rows[item].len:
      let length = int(uint32(selected.extrinsicAt(index).value.length))
      rows[item][index] = newSeq[byte](length)
      for octet in 0..<length: rows[item][index][octet] = payload[cursor+octet]
      cursor += length
  let checked = verifyExtrinsicInputs(data.package, rows, limits)
  if checked.error != ExtrinsicInputsError.None: return WorkSubmissionResult[VerifiedExtrinsics](
      status: WorkSubmissionError.ExtrinsicFailure, extrinsicReason: checked.error)
  WorkSubmissionResult[VerifiedExtrinsics](status: WorkSubmissionError.None,
      completed: checked.value)
proc completePackageSubmission*(grant: AuthorizedWorkSubmission, extrinsics: openArray[byte],
    imports: openArray[seq[VerifiedImport]], lookup: openArray[SegmentLookup],
    limits: WorkSubmissionLimits): WorkSubmissionResult[VerifiedImportInputs] =
  ## CE133 binds separately fetched availability witnesses to the original package, never a caller replacement manifest.
  let granted = grant.data
  if granted == nil: return WorkSubmissionResult[VerifiedImportInputs](
      status: WorkSubmissionError.Uninitialized)
  if granted.header.info.kind != WorkSubmissionKind.Package: return WorkSubmissionResult[
      VerifiedImportInputs](status: WorkSubmissionError.InvalidMessage)
  let verified = verifiedExtrinsics(grant, extrinsics, limits.extrinsics)
  if verified.error != WorkSubmissionError.None:
    # Preserve the genuine hash verifier cause; earlier local refusals have no child payload.
    if verified.error == WorkSubmissionError.ExtrinsicFailure: return WorkSubmissionResult[
        VerifiedImportInputs](status: WorkSubmissionError.ExtrinsicFailure,
        extrinsicReason: verified.extrinsicError)
    return WorkSubmissionResult[VerifiedImportInputs](status: verified.error)
  if lookup.len > 8: return WorkSubmissionResult[VerifiedImportInputs](
      status: WorkSubmissionError.LimitExceeded)
  let source = granted.authorization.authorizationState.value
  let mapped = checkMappings(source, lookup, limits.history)
  if mapped != WorkSubmissionError.None: return WorkSubmissionResult[VerifiedImportInputs](status: mapped)
  let bound = bindImportInputs(verified.value, imports, lookup, limits.imports)
  if bound.error != ImportInputsError.None: return WorkSubmissionResult[VerifiedImportInputs](
      status: WorkSubmissionError.BindingFailure, bindingReason: bound.error)
  WorkSubmissionResult[VerifiedImportInputs](status: WorkSubmissionError.None,
      completed: bound.value)
proc completeBundleSubmission*(grant: AuthorizedWorkSubmission, extrinsics, segments,
    proofs: openArray[byte], limits: WorkSubmissionLimits): WorkSubmissionResult[
        VerifiedImportInputs] =
  ## CE146 authenticates all three exact body messages only after real authorization; no partial table escapes.
  template fail(reason: WorkSubmissionError) =
    return WorkSubmissionResult[VerifiedImportInputs](status: reason)
  let granted = grant.data
  if granted == nil: fail(WorkSubmissionError.Uninitialized)
  let data = granted.header
  if data.info.kind != WorkSubmissionKind.Bundle: fail(WorkSubmissionError.InvalidMessage)
  if segments.len != data.info.segmentBytes: fail(WorkSubmissionError.InvalidMessage)
  if proofs.len > data.info.importCount*385: fail(WorkSubmissionError.LimitExceeded)
  if data.info.packageBytes+extrinsics.len+segments.len+proofs.len > 13904950:
    fail(WorkSubmissionError.LimitExceeded) # Each term is independently bounded before the native sum.
  if uint64(data.info.importCount) > uint64(limits.imports.entries): fail(
      WorkSubmissionError.LimitExceeded)
  if uint64(segments.len) > uint64(limits.imports.witnessBytes): fail(
      WorkSubmissionError.LimitExceeded)
  let verified = verifiedExtrinsics(grant, extrinsics, limits.extrinsics)
  if verified.error != WorkSubmissionError.None:
    # Never manufacture a child reason for an earlier exact-length or resource refusal.
    if verified.error == WorkSubmissionError.ExtrinsicFailure: return WorkSubmissionResult[
        VerifiedImportInputs](status: WorkSubmissionError.ExtrinsicFailure,
        extrinsicReason: verified.extrinsicError)
    return WorkSubmissionResult[VerifiedImportInputs](status: verified.error)
  let count = data.package.workPackageInfo.value.items
  var rows = newSeq[seq[VerifiedImport]](count)
  var position = 0
  var leafPosition = 0
  var witnessBytes = uint64(segments.len)
  for item in 0..<count:
    # Manifest order, including repeated references, defines both the raw leaf and proof partition.
    let selected = data.package.workItemAt(item).value
    rows[item] = newSeq[VerifiedImport](selected.workItemInfo.value.imports)
    for index in 0..<rows[item].len:
      if position >= proofs.len: fail(WorkSubmissionError.InvalidMessage)
      let size = decode(proofs.toOpenArray(position, proofs.high))
      if not size.ok: fail(WorkSubmissionError.InvalidMessage)
      if uint64(size.value) > 12: fail(WorkSubmissionError.LimitExceeded)
      let siblings = int(uint64(size.value))
      position += size.consumed
      if siblings > (proofs.len-position) div 32: fail(WorkSubmissionError.InvalidMessage)
      let proofBytes = uint64(siblings*32)
      if proofBytes > uint64(limits.imports.witnessBytes)-witnessBytes: fail(
          WorkSubmissionError.LimitExceeded)
      witnessBytes += proofBytes
      var path = newSeq[SegmentRoot](siblings)
      for sibling in 0..<siblings:
        for octet in 0..<32: path[sibling].bytes[octet] = proofs[position+sibling*32+octet]
      position += siblings*32
      var leaf = default(array[4104, byte])
      for octet in 0..<4104: leaf[octet] = segments[leafPosition+octet]
      leafPosition += 4104
      let reference = selected.importAt(index).value
      var root = SegmentRoot()
      case reference.kind
      of ImportKind.Root: root = reference.root
      of ImportKind.Package:
        # Structural decoding proved exact dictionary coverage before the grant was created.
        for key in 0..<data.info.mappingCount:
          if data.lookup[key].packageHash.bytes == reference.package.bytes: root = data.lookup[
              key].segmentRoot
      let checked = verifyImportSegment(root, reference.index, FetchSegment(leaf), path, limits.proof)
      if checked.error != ImportJustificationError.None: return WorkSubmissionResult[
          VerifiedImportInputs](status: WorkSubmissionError.ImportFailure,
          importReason: checked.error)
      rows[item][index] = checked.value
  if position != proofs.len: fail(WorkSubmissionError.InvalidMessage)
  var lookup = newSeq[SegmentLookup](data.info.mappingCount)
  for index in 0..<lookup.len: lookup[index] = data.lookup[
      index] # Detach fixed dictionary storage for the complete-table binder.
  let bound = bindImportInputs(verified.value, rows, lookup, limits.imports)
  if bound.error != ImportInputsError.None: return WorkSubmissionResult[VerifiedImportInputs](
      status: WorkSubmissionError.BindingFailure, bindingReason: bound.error)
  WorkSubmissionResult[VerifiedImportInputs](status: WorkSubmissionError.None,
      completed: bound.value)
