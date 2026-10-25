# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable bounded light metadata transport contains no state map, proof graph or root/chain trust authority.
## The canonical application supplies already trusted identities; copying and structural checks perform no cryptography or native IO.
import std/assertions
import ../codec/[bounded, header, state_trie]
from ../chain/genesis import BlockHash
const
  MaxRpcLightHeaders* = 8           ## Metadata retention remains finite independently of proof/state retention.
  MaxRpcLightHeaderBytes* = 1048576 ## Complete sealed metadata transport, before any copy.
  MaxRpcLightFacts* = 256           ## Local fact coverage is never a complete-state entry count.
type
  RpcLightHeaderInput* = object ## Stable caller-supplied metadata; capture validates structure, never consensus or posterior-root authority.
    blockHash*: BlockHash
    stateRoot*: StateRoot
    slot*: uint32
    wire*: seq[byte]
  RpcLightIdentity* = object ## Fixed copied display selectors are not an independently trusted checkpoint type.
    blockIdentity: BlockHash
    root: StateRoot
    time: uint32
  RpcLightHeader* = object ## Private canonical wire and fixed metadata escape only through read-only/detached getters.
    ready: bool
    selected: RpcLightIdentity
    info: HeaderInfo
    wire: seq[byte]
  SourceData = ref object ## Acyclic immutable metadata owns no application canonical head or partial proof graph.
    headers: seq[RpcLightHeader]
    profile: HeaderConfig
    facts: int
  RpcLightHead* = object ## This transport cannot be supplied to complete-map or trusted light application APIs.
    data: nil SourceData
  RpcLightSourceError* {.pure.} = enum ## Failed/default capture exposes no metadata prefix.
    Uninitialized, None, LimitExceeded, InvalidHeader
  RpcLightSourceResult* = object ## Only complete bounded metadata capture grants a usable transport source.
    case status: RpcLightSourceError
    of None: completed: RpcLightHead
    else: discard # Refusals contain reasons only.
func error*(outcome: RpcLightSourceResult): RpcLightSourceError =
  ## Observe capture policy/structure refusal before selecting metadata.
  outcome.status
func value*(outcome: RpcLightSourceResult): RpcLightHead {.requires: outcome.status ==
    RpcLightSourceError.None.} =
  ## Only a complete owned transport source escapes capture.
  outcome.completed
func valid*(head: RpcLightHead): bool =
  ## Default transport describes no current header or root.
  head.data != nil
func valid*(header: RpcLightHeader): bool =
  ## Missing retained metadata never becomes a zero-hash descriptor.
  header.ready
func sameRpcLightHead*(left, right: RpcLightHead): bool =
  ## Source incarnation includes coverage metadata; matching root/hash alone does not imply identical local knowledge.
  left.data != nil and left.data == right.data
func blockHash*(identity: RpcLightIdentity): BlockHash =
  ## Display only; the receiving client still selects root/header trust independently.
  identity.blockIdentity
func stateRoot*(identity: RpcLightIdentity): StateRoot =
  ## A copied posterior-root selector is never recomputed from partial state.
  identity.root
func slot*(identity: RpcLightIdentity): uint32 =
  ## Application slot remains separate from native publication counters.
  identity.time
func identity*(header: RpcLightHeader): RpcLightIdentity {.requires: header.ready.} =
  ## Valid retained metadata supplies only its copied fixed selectors.
  header.selected
func headerInfo*(header: RpcLightHeader): HeaderInfo {.requires: header.ready.} =
  ## Structural metadata retains no full-state provider.
  header.info
func byteLength*(header: RpcLightHeader): int =
  ## Defaults have no sealed wire to expose.
  header.wire.len
proc copyHeader*(header: RpcLightHeader, output: var openArray[byte]): bool =
  ## Insufficient destinations remain untouched; successful copies never alias immutable backing storage.
  if not header.ready or output.len < header.wire.len: return false # Preflight precedes every destination write.
  for index in 0..<header.wire.len: output[index] = header.wire[index] # Proved fixed extent.
  true
func len*(head: RpcLightHead): int =
  ## Metadata length is bounded independently of state/proof coverage.
  let data = head.data
  if data == nil: 0 else: data.headers.len
proc current*(head: RpcLightHead): RpcLightHeader {.requires: head.data != nil.} =
  ## Successful source capture always retains at least one current record.
  let data = head.data
  assert data != nil
  data.headers[data.headers.len-1]
proc stateRoot*(head: RpcLightHead): StateRoot {.requires: head.data != nil.} =
  ## Copied current metadata supplies a display selector, never independently trusted state authority.
  head.current.identity.stateRoot
proc headerAt*(head: RpcLightHead, index: int): RpcLightHeader =
  ## Unknown history remains an invalid metadata owner without fallback or native lookup.
  let data = head.data
  if data == nil or index < 0 or index >= data.headers.len: return default(
      RpcLightHeader) # No invalid index grants a descriptor.
  data.headers[index]
proc headerProfile*(head: RpcLightHead): HeaderConfig {.requires: head.data != nil.} =
  ## Caller-selected configured geometry is not an inferred verified state roster.
  let data = head.data
  assert data != nil
  data.profile
proc knownFacts*(head: RpcLightHead): int {.requires: head.data != nil.} =
  ## Coverage counts both presence and proven absence, never total complete-map keys.
  let data = head.data
  assert data != nil
  data.facts
proc captureRpcLightHead*(headers: openArray[RpcLightHeaderInput], profile: HeaderConfig,
    knownFacts: int): RpcLightSourceResult =
  ## Bounds and canonical header structure precede private copying; trust remains the application caller's separate responsibility.
  if headers.len == 0 or headers.len > MaxRpcLightHeaders or knownFacts < 0 or knownFacts >
      MaxRpcLightFacts: return RpcLightSourceResult(
      status: RpcLightSourceError.LimitExceeded) # No incomplete source or unbounded retained coverage.
  var total = 0
  for record in headers:
    # A subtraction preflight bounds all complete wire transports before allocating owned output.
    if record.wire.len == 0 or record.wire.len > 262144 or record.wire.len >
        MaxRpcLightHeaderBytes-total: return RpcLightSourceResult(
        status: RpcLightSourceError.LimitExceeded)
    total += record.wire.len
  var captured = newSeq[RpcLightHeader](headers.len)
  for index in 0..<headers.len:
    # Inspection validates exact structural consumption and slot under independently configured geometry, without hashing.
    let record = headers[index]
    let inspected = inspectHeader(record.wire, profile)
    if inspected.error != HeaderError.None: return RpcLightSourceResult(
        status: RpcLightSourceError.InvalidHeader) # No earlier captured metadata prefix escapes.
    if inspected.value.consumed != record.wire.len or uint32(inspected.value.unsigned.slot) !=
        record.slot: return RpcLightSourceResult(
        status: RpcLightSourceError.InvalidHeader) # Reject trailing transport and inconsistent display time.
    var wire = newSeq[byte](record.wire.len)
    for octet in 0..<wire.len: wire[octet] = record.wire[octet] # Caller mutation cannot change the stored source.
    captured[index] = RpcLightHeader(ready: true,
      selected: RpcLightIdentity(blockIdentity: record.blockHash, root: record.stateRoot,
          time: record.slot), info: inspected.value, wire: wire)
  RpcLightSourceResult(status: RpcLightSourceError.None,
    completed: RpcLightHead(data: SourceData(headers: captured, profile: profile,
        facts: knownFacts)))
