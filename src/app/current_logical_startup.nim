# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded explicit logical identity declarations are matched to the actual selected state before a CLI download opens peers.
## Physical map entries never invent raw identities; successful startup retains existing State parent qualification only.
import std/[syncio, strutils]
import ./current_logical_download
import ../chain/[provider, genesis, services]
import ../codec/[bounded, state_composition, state_accounts, state_service_values, state_requests, state_layout]
import ../state/[parent_profile, parent_globals, parent_logical, global_snapshot,
    supplied_logical_inventory, supplied_services, store]

const CurrentLogicalSourceBytes* = 65536 ## Startup transport cap is independent of retained declarations and decoded payload policies.
const CurrentLogicalSourceHeader* = "ragnarok-current-logical-source-v1" ## Shared existing v1 identity-only transport header; export and parser accept one representation.
const CurrentLogicalSourceKeyBytes* = 4096 ## Shared v1 raw-identity syntax ceiling also bounds canonical export.
const CurrentLogicalSourceLines* = 4096 ## Fixed syntax cap bounds duplicate-service preflight and native ordinal conversions.
type
  CurrentLogicalStartupLimits* = object ## Every actual-source projection, full parent qualification and later continuation policy is explicit.
    projection*: SuppliedServicesLimits
    profile*: ParentProfileLimits
    globals*: GlobalStateLimits
    logical*: SuppliedLogicalLimits
    download*: CurrentLogicalDownloadLimits
  DeclarationKind {.pure.} = enum ## Only explicitly named service/raw-key/preimage/request identities are admitted.
    Service, Storage, Preimage, Request
  Declaration = object ## Private rows retain decoded raw identities; no input text or canonical graph borrow escapes parsing.
    kind: DeclarationKind
    owner: int
    service: ServiceIndex
    key: seq[byte]
    hash: ServicePreimageHash
    length: RequestLength
  DeclarationData = ref object ## Immutable acyclic syntax owner contains no successful canonical or producer authority.
    rows: seq[Declaration]
    services: int
    bytes: uint64
  CurrentLogicalDeclarations* = object ## Only complete bounded syntax validation creates this private immutable owner.
    data: nil DeclarationData
  CurrentLogicalStartupError* {.pure.} = enum ## Syntax/transport/projection refusals stay separate from genuine State qualification failures.
    Uninitialized, None, FileFailure, LimitExceeded, WrongVersion, InvalidLine, MissingService,
      InvalidNumber, InvalidHex, DuplicateService, InvalidSource, SourceFailure, ProfileFailure,
      GlobalsFailure, LogicalFailure
  CurrentLogicalStartupResult*[T] = object ## Failed/default alternatives expose no declarations, partial services or qualified policy.
    case status: CurrentLogicalStartupError
    of None:
      completed: T
    of SourceFailure:
      sourceReason: ServiceReadError
    of ProfileFailure:
      profileReason: ParentProfileResult[SelectedParentProfile]
    of GlobalsFailure:
      globalsReason: ParentGlobalsResult[SelectedParentGlobals]
    of LogicalFailure:
      logicalReason: ParentLogicalResult[SelectedLogicalParent]
    else:
      discard # Plain lexical/resource/default errors retain no successful source prefix.
func error*[T](outcome: CurrentLogicalStartupResult[T]): CurrentLogicalStartupError =
  ## Inspect the immutable selected startup stage.
  outcome.status
func value*[T](outcome: CurrentLogicalStartupResult[T]): T {.inline,
    requires: outcome.status == CurrentLogicalStartupError.None.} =
  ## Extract only complete parsed declarations or a genuinely qualified source policy.
  outcome.completed
func sourceFailure*[T](outcome: CurrentLogicalStartupResult[T]): ServiceReadError {.inline,
    requires: outcome.status == CurrentLogicalStartupError.SourceFailure.} =
  ## Preserve actual missing/malformed/backend service reads without treating absence as empty bytes.
  outcome.sourceReason
func profileFailure*[T](outcome: CurrentLogicalStartupResult[T]): ParentProfileResult[
    SelectedParentProfile] {.inline,

requires: outcome.status == CurrentLogicalStartupError.ProfileFailure.} =
  ## Preserve original selected-view/previous-roster refusal.
  outcome.profileReason
func globalsFailure*[T](outcome: CurrentLogicalStartupResult[T]): ParentGlobalsResult[
    SelectedParentGlobals] {.inline,

requires: outcome.status == CurrentLogicalStartupError.GlobalsFailure.} =
  ## Preserve actual all-global qualification failure.
  outcome.globalsReason
func logicalFailure*[T](outcome: CurrentLogicalStartupResult[T]): ParentLogicalResult[
    SelectedLogicalParent] {.inline,

requires: outcome.status == CurrentLogicalStartupError.LogicalFailure.} =
  ## Preserve exact complete-map matching/capture refusal, including omitted or duplicate namespace identities.
  outcome.logicalReason
func fail[T](reason: CurrentLogicalStartupError): CurrentLogicalStartupResult[T] =
  ## Construct only a payload-free refusal.
  CurrentLogicalStartupResult[T](status: reason)
proc decimal(text: string, maximum: uint64, value: var uint64): bool =
  ## Canonical decimal parsing checks each multiply/add before conversion; reserved request lengths are excluded by the caller's maximum.
  value = 0
  if text.len == 0 or text.len > 10 or (text.len > 1 and text[0] == '0'): return false
  for character in text:
    if character notin {'0'..'9'}: return false # No sign, whitespace, exponent or alternate numeric encoding.
    let digit = uint64(ord(character)-ord('0'))
    if digit > maximum or value > (maximum-digit) div 10: return false
    value = value*10+digit
  true
func nibble(character: char): int =
  ## Lowercase hexadecimal has one canonical representation; no uppercase or prefix fallback.
  if character in {'0'..'9'}: ord(character)-ord('0')
  elif character in {'a'..'f'}: ord(character)-ord('a')+10
  else: -1
proc decodeCurrentLogicalDeclarations*(text: string,
    limits: SuppliedServicesLimits): CurrentLogicalStartupResult[CurrentLogicalDeclarations] =
  ## Count/admit the whole fixed row array before allocation, then decode explicit identities without any state lookup or hashing.
  type Output = CurrentLogicalDeclarations
  if text.len > CurrentLogicalSourceBytes: return fail[Output](
      CurrentLogicalStartupError.LimitExceeded)
  var position, count, services, line = 0
  # The first pass bounds all descriptor allocation and service traversal before retaining raw identities.
  while position < text.len:
    let first = position
    while position < text.len and text[position] != '\n': inc position
    let extent = position-first
    if line == 0:
      if extent != CurrentLogicalSourceHeader.len or text.substr(first, position-1) != CurrentLogicalSourceHeader:
        return fail[Output](CurrentLogicalStartupError.WrongVersion)
    elif extent > 0 and text[first] != '#':
      inc count
      if extent >= 2 and text[first] == 's' and text[first+1] == '=': inc services
      let tooManyFacts = uint64(count) > uint64(limits.facts)
      let tooManyServices = uint64(services) > uint64(limits.services)
      if count > CurrentLogicalSourceLines or tooManyFacts or tooManyServices:
        return fail[Output](CurrentLogicalStartupError.LimitExceeded)
    inc line
    if position < text.len: inc position # Consume only the proven LF; final newline is optional.
  if line == 0: return fail[Output](CurrentLogicalStartupError.WrongVersion)
  var remaining = min(uint64(limits.bytes), uint64(high(int)))
  if uint64(sizeof(DeclarationData)) > remaining: return fail[Output](
      CurrentLogicalStartupError.LimitExceeded)
  remaining-=uint64(sizeof(DeclarationData))
  if uint64(count) > remaining div uint64(sizeof(Declaration)): return fail[Output](
      CurrentLogicalStartupError.LimitExceeded)
  remaining-=uint64(count)*uint64(sizeof(Declaration))
  var rows = newSeq[Declaration](count)
  position = 0
  line = 0
  var ordinal = 0
  var selected = -1
  # Decode only complete rows under the already admitted native array extent.
  while position < text.len:
    let first = position
    while position < text.len and text[position] != '\n': inc position
    let extent = position-first
    if line > 0 and extent > 0 and text[first] != '#':
      if extent < 2 or text[first+1] != '=': return fail[Output](
          CurrentLogicalStartupError.InvalidLine)
      let kind = text[first]
      var row = default(Declaration)
      row.owner = selected
      if kind == 's':
        var id = 0'u64
        if not decimal(text.substr(first+2, position-1), uint64(high(uint32)), id): return fail[
            Output](CurrentLogicalStartupError.InvalidNumber)
        for index in 0..<ordinal:
          if rows[index].kind == DeclarationKind.Service and uint32(rows[index].service) == uint32(id):
            return fail[Output](CurrentLogicalStartupError.DuplicateService)
        row.kind = DeclarationKind.Service
        row.service = ServiceIndex(uint32(id))
        selected = ordinal
        row.owner = ordinal # Children refer to this exact private service declaration ordinal.
      else:
        if selected < 0: return fail[Output](CurrentLogicalStartupError.MissingService)
        if kind notin {'k', 'p', 'r'}: return fail[Output](CurrentLogicalStartupError.InvalidLine)
        row.service = rows[selected].service
        row.kind = if kind == 'k': DeclarationKind.Storage elif kind ==
            'p': DeclarationKind.Preimage else: DeclarationKind.Request
        let digits = if kind == 'r': 64 else: extent-2
        if kind == 'r' and (extent < 68 or text[first+66] != ':'): return fail[Output](
            CurrentLogicalStartupError.InvalidLine)
        if kind == 'p' and digits != 64: return fail[Output](CurrentLogicalStartupError.InvalidHex)
        if digits mod 2 != 0: return fail[Output](CurrentLogicalStartupError.InvalidHex)
        let bytes = digits div 2
        if bytes > CurrentLogicalSourceKeyBytes or uint64(bytes) > uint64(
            limits.perValue): return fail[Output](CurrentLogicalStartupError.LimitExceeded)
        var hash = default(array[32, byte])
        if kind == 'k':
          if uint64(bytes) > remaining: return fail[Output](
              CurrentLogicalStartupError.LimitExceeded)
          remaining-=uint64(bytes)
          row.key = newSeq[byte](bytes) # Only original raw keys need variable-length retained backing.
        for index in 0..<bytes:
          let a = nibble(text[first+2+index*2])
          let b = nibble(text[first+3+index*2])
          if a < 0 or b < 0: return fail[Output](CurrentLogicalStartupError.InvalidHex)
          let octet = byte(a*16+b)
          if kind == 'k': row.key[index] = octet
          else: hash[index] = octet # Hash forms were proved exactly 32 bytes before this fixed indexing.
        row.hash = ServicePreimageHash(hash)
        if kind == 'r':
          var length = 0'u64
          if not decimal(text.substr(first+67, position-1), uint64(high(uint32)-2), length):
            return fail[Output](CurrentLogicalStartupError.InvalidNumber)
          row.length = RequestLength(uint32(length))
      rows[ordinal] = row
      inc ordinal
    inc line
    if position < text.len: inc position
  let data = DeclarationData(rows: rows, services: services, bytes: min(uint64(limits.bytes),
      uint64(high(int)))-remaining)
  CurrentLogicalStartupResult[Output](status: CurrentLogicalStartupError.None, completed: Output(data: data))
proc loadCurrentLogicalDeclarations*(path: string,
    limits: SuppliedServicesLimits): CurrentLogicalStartupResult[
        CurrentLogicalDeclarations] {.raises.} =
  ## Detect oversized and growing files with cap+1 read; no source payload or native network is touched here.
  var file: File = nil
  if path.len == 0 or not open(file, path, fmRead): return fail[CurrentLogicalDeclarations](
      CurrentLogicalStartupError.FileFailure)
  defer: close(file)
  var text = newString(CurrentLogicalSourceBytes+1)
  let buffer = text.beginStore(text.len)
  let count = readBuffer(file, cast[pointer](buffer), text.len)
  text.endStore()
  if count < 0: return fail[CurrentLogicalDeclarations](CurrentLogicalStartupError.FileFailure)
  if count > CurrentLogicalSourceBytes: return fail[CurrentLogicalDeclarations](
      CurrentLogicalStartupError.LimitExceeded)
  text.setLen(count)
  decodeCurrentLogicalDeclarations(text, limits)
proc sourceValue(source: StateStoreSnapshot, key: StateKey, perValue: ByteLimit,
    available: var uint64): CurrentLogicalStartupResult[StateValue] =
  ## Admit the immutable cached extent before any payload copy; primitive read failure and absence remain typed.
  let found = source.lookup(key)
  if found.error != StateStoreError.None:
    return CurrentLogicalStartupResult[StateValue](status: CurrentLogicalStartupError.SourceFailure,
        sourceReason: if found.error == StateStoreError.MissingKey: ServiceReadError.Missing else: ServiceReadError.BackendFailure)
  let size = uint64(found.value.byteLength)
  if size > uint64(perValue) or size > available: return fail[StateValue](
      CurrentLogicalStartupError.LimitExceeded)
  available-=size
  CurrentLogicalStartupResult[StateValue](status: CurrentLogicalStartupError.None,
      completed: found.value)
proc captureCurrentLogicalStartup*(view: ChainView, declarations: CurrentLogicalDeclarations,
    limits: CurrentLogicalStartupLimits): CurrentLogicalStartupResult[
        CurrentLogicalDownloadPolicy] =
  ## Rebuild only explicitly declared identities from the actual selected state, then require existing whole-map parent matching under independent budgets.
  type Output = CurrentLogicalDownloadPolicy
  let borrowed = declarations.data
  if borrowed == nil: return fail[Output](CurrentLogicalStartupError.InvalidSource)
  let data: DeclarationData = borrowed
  let projection = limits.projection
  if uint64(data.services) > uint64(projection.services) or uint64(data.rows.len) > uint64(
      projection.facts):
    return fail[Output](CurrentLogicalStartupError.LimitExceeded)
  for row in data.rows:
    if row.kind == DeclarationKind.Storage and uint64(row.key.len) > uint64(projection.perValue):
      return fail[Output](CurrentLogicalStartupError.LimitExceeded) # A later tighter caller policy cannot inherit larger raw-key hashing permission.
  var available = min(uint64(projection.bytes), uint64(high(int)))
  template charge(amount: uint64) =
    if amount > available: return fail[Output](CurrentLogicalStartupError.LimitExceeded)
    available-=amount
  charge(data.bytes)
  if uint64(data.services) > available div uint64(sizeof(StateService)): return fail[Output](
      CurrentLogicalStartupError.LimitExceeded)
  charge(uint64(data.services)*uint64(sizeof(StateService)))
  let profile = captureParentProfile(view, limits.profile)
  if profile.error != ParentProfileError.None:
    return CurrentLogicalStartupResult[Output](status: CurrentLogicalStartupError.ProfileFailure,
        profileReason: profile)
  let globals = qualifyParentGlobals(profile.value, limits.globals)
  if globals.error != ParentGlobalsError.None:
    return CurrentLogicalStartupResult[Output](status: CurrentLogicalStartupError.GlobalsFailure,
        globalsReason: globals)
  let head = view.bestBlock
  if head.error != GenesisError.None: return fail[Output](CurrentLogicalStartupError.InvalidSource)
  let snapshot = profile.value.parentContext.value.state
  var output = newSeq[StateService](data.services)
  var selected = -1
  # Each service's exact child arrays are counted and admitted before their first payload read or allocation.
  for ordinal, row in data.rows:
    if row.kind == DeclarationKind.Service:
      inc selected
      var storage, preimages, requests = 0
      for next in ordinal+1..<data.rows.len:
        if data.rows[next].owner == ordinal:
          case data.rows[next].kind
          of DeclarationKind.Storage: inc storage
          of DeclarationKind.Preimage: inc preimages
          of DeclarationKind.Request: inc requests
          else: discard # Service rows name their own ordinal and cannot be children.
      for amount in [uint64(storage)*uint64(sizeof(StateStorageItem)), uint64(preimages)*uint64(
          sizeof(StatePreimageItem)), uint64(requests)*uint64(sizeof(StateRequestItem))]: charge(amount)
      if uint64(ServiceMetadataBytes) > uint64(projection.perValue): return fail[Output](
          CurrentLogicalStartupError.LimitExceeded)
      let found = sourceValue(snapshot, chapterServiceKey(StateChapter(255), row.service),
          ByteLimit(ServiceMetadataBytes), available)
      if found.error != CurrentLogicalStartupError.None:
        if found.error == CurrentLogicalStartupError.SourceFailure:
          return CurrentLogicalStartupResult[Output](
              status: CurrentLogicalStartupError.SourceFailure, sourceReason: found.sourceFailure)
        return fail[Output](found.error)
      let metadata = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
      if metadata.error != ServiceMetadataError.None:
        return CurrentLogicalStartupResult[Output](status: CurrentLogicalStartupError.SourceFailure,
            sourceReason: ServiceReadError.Malformed)
      output[selected] = StateService(service: row.service, metadata: metadata.value.metadata,
          storage: newSeq[StateStorageItem](storage), preimages: newSeq[StatePreimageItem](
              preimages), requests: newSeq[StateRequestItem](requests))
      var s, p, r = 0
      # No row outside this explicit owner may supply a payload, hash or request history.
      for next in ordinal+1..<data.rows.len:
        let child = data.rows[next]
        if child.owner == ordinal:
          case child.kind
          of DeclarationKind.Storage, DeclarationKind.Preimage:
            let derived = if child.kind == DeclarationKind.Storage: serviceStorageKey(row.service,
                child.key, ByteLimit(CurrentLogicalSourceKeyBytes))
              else: servicePreimageKey(row.service, child.hash, ByteLimit(32))
            if derived.error != ServiceValueError.None:
              return CurrentLogicalStartupResult[Output](
                  status: CurrentLogicalStartupError.SourceFailure,
                  sourceReason: ServiceReadError.BackendFailure)
            let value = sourceValue(snapshot, derived.value, projection.perValue, available)
            if value.error != CurrentLogicalStartupError.None:
              if value.error == CurrentLogicalStartupError.SourceFailure:
                return CurrentLogicalStartupResult[Output](
                    status: CurrentLogicalStartupError.SourceFailure,
                    sourceReason: value.sourceFailure)
              return fail[Output](value.error) # Cached actual extent was refused before payload copying.
            if child.kind == DeclarationKind.Storage:
              output[selected].storage[s] = StateStorageItem(key: child.key,
                  value: value.value.bytes)
              inc s
            else:
              output[selected].preimages[p] = StatePreimageItem(hash: child.hash,
                  value: value.value.bytes)
              inc p
          of DeclarationKind.Request:
            let derived = serviceRequestKey(row.service, child.hash, child.length, ByteLimit(32))
            if derived.error != RequestError.None:
              return CurrentLogicalStartupResult[Output](
                  status: CurrentLogicalStartupError.SourceFailure,
                  sourceReason: ServiceReadError.BackendFailure)
            let value = sourceValue(snapshot, derived.value, ByteLimit(min(uint64(
                projection.perValue), 13'u64)), available)
            if value.error != CurrentLogicalStartupError.None:
              if value.error == CurrentLogicalStartupError.SourceFailure:
                return CurrentLogicalStartupResult[Output](
                    status: CurrentLogicalStartupError.SourceFailure,
                    sourceReason: value.sourceFailure)
              return fail[Output](value.error)
            let wire = value.value.bytes
            let history = decodeRequestHistory(wire, RequestHistoryConfig(items: ElementLimit(3),
                maxBytes: ByteLimit(13)))
            if history.error != RequestError.None or history.value.consumed != wire.len:
              return CurrentLogicalStartupResult[Output](
                  status: CurrentLogicalStartupError.SourceFailure,
                  sourceReason: ServiceReadError.Malformed)
            output[selected].requests[r] = StateRequestItem(hash: child.hash, length: child.length,
                history: history.value.history)
            inc r
          else: discard # Service declarations cannot enter a child array.
  let parent = captureLogicalParent(globals.value, output, limits.logical)
  if parent.error != ParentLogicalError.None:
    return CurrentLogicalStartupResult[Output](status: CurrentLogicalStartupError.LogicalFailure,
        logicalReason: parent)
  CurrentLogicalStartupResult[Output](status: CurrentLogicalStartupError.None,
      completed: initCurrentLogicalDownloadPolicy(parent.value, limits.download))
