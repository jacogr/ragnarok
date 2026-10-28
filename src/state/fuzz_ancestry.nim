# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fuzzer initial hash/slot facts remain distinct from actual child-header lookup-root evidence and production ancestry.
import std/assertions
import ./fuzz_protocol as state_fuzz_protocol
import ../codec/bounded as codec_bounded
import ../codec/header as codec_header
import ../crypto/primitives as crypto_primitives

type
  FuzzAncestorIndex* = distinct int ## A context-bound ordinal is not a timeslot or a header identity.
  FuzzAncestryLimits* = object ## Metadata bytes and retained known-header bytes share one explicit local ceiling.
    header*: HeaderConfig
    records*: ElementLimit
    bytes*: ByteLimit
  FuzzAncestryError* {.pure.} = enum ## Failures expose no partial context, fabricated header or guessed lookup root.
    Uninitialized, None, InvalidConfig, InvalidHeader, LimitExceeded, ConflictingRecord,
    WrongParent, InvalidSlot, BackendFailure, InvalidIndex, MissingLookupAnchor,
    WrongLookupSlot, MissingLookupChild, WrongLookupState
  FuzzAncestryResult*[T] = object ## Complete immutable context/evidence is selected separately from every reason-only failure.
    case status: FuzzAncestryError
    of None: completed: T
    else: discard # No failure contains a usable membership prefix or lookup certificate.
  FuzzAncestryInfo* = object ## Copied scalar retention and head observations reveal no mutable sequence or native authority.
    records*, knownHeaders*: int
    bytes*: uint64
    head*: FuzzAncestor
  Fact = object ## Initial membership lacks a header owner; only an actually captured header may prove a child's prior root.
    member: FuzzAncestor
    header: OwnedHeader
  AncestryData = ref object ## Private acyclic immutable snapshots make fork restoration independent of later imports.
    records: seq[Fact]
    profile: HeaderConfig
    bytes: uint64
  FuzzAncestry* = object ## Default is invalid; copying shares only immutable test-context facts.
    data: nil AncestryData
  CapturedHeader = object ## One private capture binds its copied hash/slot to exact full sealed bytes.
    fact: Fact
    bytes: uint64
func error*[T](outcome: FuzzAncestryResult[T]): FuzzAncestryError =
  ## Inspect only the immutable selected reason.
  outcome.status
func value*[T](outcome: FuzzAncestryResult[T]): T {.inline,
    requires: outcome.status == FuzzAncestryError.None.} =
  ## Extract only a complete successful value.
  outcome.completed
func refused[T](reason: FuzzAncestryError): FuzzAncestryResult[T] =
  ## Centralize failure without publishing a prefix of a purported ancestry.
  FuzzAncestryResult[T](status: reason)
func valid(limits: FuzzAncestryLimits): bool =
  ## Local retention is finite and nonzero; the wire schema independently caps initial records at24.
  uint64(limits.records) > 0 and uint64(limits.records) <= 14400 and uint64(limits.bytes) >= 36
proc capture(source: OwnedHeader, limits: FuzzAncestryLimits): FuzzAncestryResult[CapturedHeader] =
  ## Re-decode under this consumer's profile before hashing exact sealed bytes; no borrowed input survives.
  let info = source.headerInfo
  if info.error != HeaderError.None: return refused[CapturedHeader](FuzzAncestryError.InvalidHeader)
  let size = uint64(info.value.consumed)
  if size > uint64(limits.header.maxBytes) or size > uint64(limits.bytes):
    return refused[CapturedHeader](FuzzAncestryError.LimitExceeded)
  var wire = newSeq[byte](info.value.consumed)
  if source.encodeOwnedHeader(wire).error != HeaderError.None:
    return refused[CapturedHeader](FuzzAncestryError.InvalidHeader)
  let decoded = decodeHeader(wire, limits.header)
  if decoded.error == HeaderError.InvalidConfig: return refused[CapturedHeader](
      FuzzAncestryError.InvalidConfig)
  if decoded.error != HeaderError.None or decoded.value.consumed != wire.len:
    return refused[CapturedHeader](FuzzAncestryError.InvalidHeader)
  let hashed = blake2b256(wire)
  if hashed.error != CryptoError.None: return refused[CapturedHeader](
      FuzzAncestryError.BackendFailure)
  let fact = Fact(member: FuzzAncestor(slot: decoded.value.owner.headerInfo.value.unsigned.slot,
      hash: FuzzHeaderHash(array[32, byte](hashed.value))), header: decoded.value.owner)
  FuzzAncestryResult[CapturedHeader](status: FuzzAncestryError.None,
      completed: CapturedHeader(fact: fact, bytes: size))
proc captureFuzzAncestry*(seed: OwnedHeader, declared: openArray[FuzzAncestor],
    limits: FuzzAncestryLimits): FuzzAncestryResult[FuzzAncestry] =
  ## Initial membership is an explicit fuzz seed assumption; it is not full-header authentication or root evidence.
  if not limits.valid: return refused[FuzzAncestry](FuzzAncestryError.InvalidConfig)
  if declared.len > 24: return refused[FuzzAncestry](FuzzAncestryError.LimitExceeded)
  let head = capture(seed, limits)
  if head.error != FuzzAncestryError.None: return refused[FuzzAncestry](head.error)
  let first = head.value.fact.member
  var includesSeed = false
  for index, member in declared:
    for prior in 0..<index:
      if uint32(declared[prior].slot) == uint32(member.slot) or
          array[32, byte](declared[prior].hash) == array[32, byte](member.hash):
        return refused[FuzzAncestry](FuzzAncestryError.ConflictingRecord)
    if array[32, byte](member.hash) == array[32, byte](first.hash):
      if uint32(member.slot) != uint32(first.slot): return refused[FuzzAncestry](
          FuzzAncestryError.InvalidSlot)
      includesSeed = true # The explicit seed owner supplies the header rather than allocating a duplicate fact.
    elif uint32(member.slot) >= uint32(first.slot):
      return refused[FuzzAncestry](FuzzAncestryError.InvalidSlot)
  let count = declared.len+(if includesSeed: 0 else: 1)
  let metadata = uint64(count)*36 # The independent initial cap proves this multiplication cannot overflow.
  if uint64(count) > uint64(limits.records) or metadata > uint64(limits.bytes):
    return refused[FuzzAncestry](FuzzAncestryError.LimitExceeded)
  if head.value.bytes > uint64(limits.bytes)-metadata:
    return refused[FuzzAncestry](FuzzAncestryError.LimitExceeded)
  var records = @[head.value.fact]
  for member in declared:
    if array[32, byte](member.hash) != array[32, byte](first.hash): records.add(Fact(
        member: member))
  for index in 1..<records.len:
    var position = index
    while position > 0 and uint32(records[position-1].member.slot) < uint32(records[
        position].member.slot):
      swap(records[position-1], records[position]) # Canonical context order is independent of message order.
      dec position
  FuzzAncestryResult[FuzzAncestry](status: FuzzAncestryError.None, completed: FuzzAncestry(
    data: AncestryData(records: records, profile: limits.header, bytes: metadata+head.value.bytes)))
proc fuzzAncestryInfo*(context: FuzzAncestry): FuzzAncestryResult[FuzzAncestryInfo] =
  ## Return only copied observations from one initialized immutable context.
  let data = context.data
  if data == nil: return refused[FuzzAncestryInfo](FuzzAncestryError.Uninitialized)
  var known = 0
  for position in 0..<data.records.len:
    let fact = data.records[position]
    if fact.header.headerInfo.error == HeaderError.None: inc known # Unknown initial facts never acquire a synthetic full header.
  FuzzAncestryResult[FuzzAncestryInfo](status: FuzzAncestryError.None,
      completed: FuzzAncestryInfo(records: data.records.len, knownHeaders: known,
        bytes: data.bytes, head: data.records[0].member))
proc fuzzAncestorAt*(context: FuzzAncestry, index: FuzzAncestorIndex): FuzzAncestryResult[FuzzAncestor] =
  ## Copied nominal membership survives source release without exporting sequence backing storage.
  let data = context.data
  if data == nil: return refused[FuzzAncestor](FuzzAncestryError.Uninitialized)
  if int(index) < 0 or int(index) >= data.records.len: return refused[FuzzAncestor](
      FuzzAncestryError.InvalidIndex)
  FuzzAncestryResult[FuzzAncestor](status: FuzzAncestryError.None, completed: data.records[int(index)].member)
proc validateFuzzParent*(context: FuzzAncestry, parent: OwnedHeader,
    limits: FuzzAncestryLimits): FuzzAncestryError =
  ## A reused context must match the exact current parent and this consumer's profile/budgets.
  let data = context.data
  if data == nil: return FuzzAncestryError.Uninitialized
  if not limits.valid: return FuzzAncestryError.InvalidConfig
  if uint64(data.profile.cores) != uint64(limits.header.cores) or
      uint64(data.profile.authorValidators) != uint64(limits.header.authorValidators) or
      uint64(data.profile.epochSlots) != uint64(limits.header.epochSlots): return FuzzAncestryError.InvalidConfig
  if uint64(data.records.len) > uint64(limits.records) or data.bytes > uint64(limits.bytes):
    return FuzzAncestryError.LimitExceeded
  for position in 0..<data.records.len:
    let fact = data.records[position]
    let info = fact.header.headerInfo
    if info.error == HeaderError.None and uint64(info.value.consumed) > uint64(
        limits.header.maxBytes):
      return FuzzAncestryError.LimitExceeded
  let selected = capture(parent, limits)
  if selected.error != FuzzAncestryError.None: return selected.error
  if array[32, byte](selected.value.fact.member.hash) != array[32, byte](data.records[
      0].member.hash):
    return FuzzAncestryError.WrongParent
  FuzzAncestryError.None
proc extendFuzzAncestry*(context: FuzzAncestry, child: OwnedHeader,
    limits: FuzzAncestryLimits): FuzzAncestryResult[FuzzAncestry] =
  ## Restore an old branch context by value; a successful append never mutates the source or another sibling.
  let data = context.data
  if data == nil: return refused[FuzzAncestry](FuzzAncestryError.Uninitialized)
  let admitted = context.validateFuzzParent(data.records[0].header, limits)
  if admitted != FuzzAncestryError.None: return refused[FuzzAncestry](admitted)
  let captured = capture(child, limits)
  if captured.error != FuzzAncestryError.None: return refused[FuzzAncestry](captured.error)
  let fields = captured.value.fact.header.headerInfo.value.unsigned
  if array[32, byte](fields.parent) != array[32, byte](data.records[0].member.hash):
    return refused[FuzzAncestry](FuzzAncestryError.WrongParent)
  if uint32(fields.slot) <= uint32(data.records[0].member.slot):
    return refused[FuzzAncestry](FuzzAncestryError.InvalidSlot)
  for position in 0..<data.records.len:
    let fact = data.records[position]
    if array[32, byte](fact.member.hash) == array[32, byte](captured.value.fact.member.hash):
      return refused[FuzzAncestry](FuzzAncestryError.ConflictingRecord)
  if captured.value.bytes > uint64(limits.bytes)-36:
    return refused[FuzzAncestry](FuzzAncestryError.LimitExceeded)
  var available = uint64(limits.bytes)-36-captured.value.bytes
  var records = @[captured.value.fact]
  for position in 0..<data.records.len:
    let fact = data.records[position]
    var bytes = 36'u64
    let info = fact.header.headerInfo
    if info.error == HeaderError.None: bytes += uint64(
        info.value.consumed) # Count only actual retained full-header owners.
    if uint64(records.len) >= uint64(limits.records) or bytes >
        available: break # Retain one contiguous newest-first prefix within both quotas.
    records.add(fact)
    available -= bytes
  FuzzAncestryResult[FuzzAncestry](status: FuzzAncestryError.None, completed: FuzzAncestry(
    data: AncestryData(records: records, profile: limits.header, bytes: uint64(
        limits.bytes)-available)))
proc findFuzzLookup*(context: FuzzAncestry, hash: FuzzHeaderHash, slot: HeaderSlot,
    root: PriorStateRoot): FuzzAncestryResult[FuzzAncestorIndex] =
  ## A hash/slot record alone never proves a posterior root; require an actual retained child and compare its exact prior root.
  let data = context.data
  if data == nil: return refused[FuzzAncestorIndex](FuzzAncestryError.Uninitialized)
  for index in 0..<data.records.len:
    let fact = data.records[index]
    if array[32, byte](fact.member.hash) == array[32, byte](hash):
      if uint32(fact.member.slot) != uint32(slot): return refused[FuzzAncestorIndex](
          FuzzAncestryError.WrongLookupSlot)
      for childIndex in 0..<data.records.len:
        let newer = data.records[childIndex]
        let info = newer.header.headerInfo
        if info.error == HeaderError.None and array[32, byte](info.value.unsigned.parent) == array[
            32, byte](hash):
          if array[32, byte](info.value.unsigned.priorState) != array[32, byte](root):
            return refused[FuzzAncestorIndex](FuzzAncestryError.WrongLookupState)
          return FuzzAncestryResult[FuzzAncestorIndex](status: FuzzAncestryError.None,
              completed: FuzzAncestorIndex(index))
      return refused[FuzzAncestorIndex](FuzzAncestryError.MissingLookupChild)
  refused[FuzzAncestorIndex](FuzzAncestryError.MissingLookupAnchor)
