# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Source-bound static control flow for a bounded native graph. Up to 255 ranked source
## blocks share one optional arena, bounded by 256 KiB of published code and 4 KiB per entry.
## The source-header map has 512 slots so even the largest graph stays below half-full.
## The block cap bounds copied source IR independently of guest iteration counts. Original block
## prices and source attempts remain independent. Lowering can link only positive checked successors.
## Each native entry commits a bounded number of original reservations and returns their order.
## A byte per visit is appended to fixed call-local word storage; the returned visit count
## bounds every read. Unwritten tail bytes need no clearing and never participate in a receipt key.
## The checked bridge verifies this receipt before exposing a successor or resuming a paid
## memory operation. A segment may reuse validation of the same immutable source path.
## Fault handling and dynamic control remain with the checked stream.

import ./[jit_rules, native_ir, native_mixed_loop, native_read_body]

const
  NativeFusionTrainingFloor* = 524288'u64                   ## Prior settled attempts before a sampling segment.
  NativeFusionBlockLimit* = 255 ## One ranked graph; one-based byte tokens exclude zero.
  NativeFusionSlotLimit* = 512 ## Keep the largest byte-token graph below half-full in the checked map.
  NativeFusionVisitLimit* = 64 ## Fixed entry horizon, independent of the graph's block cap.
  NativeFusionPathWords* = (NativeFusionVisitLimit+7) div 8 ## Fixed ordered byte-log storage.
  NativeFusionImageLimit* = 256*1024 ## Published graph bytes, including every entry and alignment padding.
  NativeFusionGasOffset* = NativeMixedLoopContextBytes
  NativeFusionQuotaOffset* = NativeFusionGasOffset+8
  NativeFusionPathOffset* = NativeFusionQuotaOffset+8
  NativeFusionVisitsOffset* = NativeFusionPathOffset+NativeFusionPathWords*8
  NativeFusionPaidOffset* = NativeFusionVisitsOffset+8

when NativeFusionSlotLimit != 512 or NativeFusionBlockLimit*2 > NativeFusionSlotLimit:
  {.error: "native fusion header hashing requires its fixed half-full 512-slot map".}

when NativeFusionBlockLimit < 1 or NativeFusionBlockLimit > 255:
  {.error: "native fusion graph tokens must fit a nonzero byte".}

when NativeFusionVisitLimit < 1 or NativeFusionVisitLimit > 64:
  {.error: "native fusion entry history must stay within its checked 1..64 visit bound".}

type
  NativeFusionPath* = array[NativeFusionPathWords, uint64]
    ## Tokens occupy successive low-to-high bytes in the native little-endian context.
  NativeFusionBlock* = object
    ## The source walk copies only verified non-noop body operations. Targets are
    ## [false, true]; a missing first target leaves the terminal to checked execution.
    header*, terminal*, first*, span*: uint32
    price*: uint64
    targets*: array[2, uint32]
    branch*: NativeOperation
    operations*: array[int(NativeReadFactLimit)-1, NativeOperation]
    guards*: uint32 ## Only these body nodes can be returned as paid refusals.
  NativeFusionContext* = object
    ## Call-local descriptors and ledger precede a fixed byte log and its returned count.
    ## Each native entry overwrites only its used prefix; unused bytes have no receipt authority.
    memory*: NativeMixedLoopContext
    gas*, remaining*: uint64
    path*: NativeFusionPath
    visits*, paid*: uint64
  NativeFusionExit* = object
    ## A successful validation also carries the proved final source token; the bridge need not decode it again.
    valid*, branches*: bool
    paidHeader*, attempted*, lastToken*: uint32

  NativeFusionReceipt = object
    ## A verified path may be reused only by the same segment and immutable graph.
    path: NativeFusionPath
    visits, gas: uint64
    entry, next: uint32
    receipt: NativeFusionExit
  NativeFusionReceipts* = array[256, NativeFusionReceipt]
    ## Segment-local cache of successful path proofs for exactly one borrowed graph.

func nativeFusionSlot*(token: uint32): int {.inline.} =
  ## A one-based source-header token hashes into the fixed 512-slot, at-most-half-full map.
  ## Zero can be hashed but never confers source or entry authority.
  int((token*0x9e3779b9'u32) shr 23)

func complete*(item: NativeFusionBlock): bool =
  ## Validate copied scalar geometry and all supported opcode and guard identities.
  if item.header >= item.terminal or item.terminal >= NativeEntryLimit or item.span == 0 or
      item.span > NativeReadFactLimit or item.terminal-item.header > item.span or
      item.first > high(uint32)-(item.span-1):
    return false
  let count = int(item.terminal-item.header)-1
  var guards = 0'u32
  for index in 0..<count:
    # Dynamic memory may decline at its original site after earlier effects.
    let op = item.operations[index].opcode
    if nativeMixedLoopStoreWidth(op) != 0 or nativeReadOpcode(nativeReadEncodingOpcode(op)):
      guards = guards or (1'u32 shl index)
    elif not supportedScalarOpcode(op):
      return false
  if guards != item.guards: return false
  let no = item.targets[0]
  let yes = item.targets[1]
  if no == NativeEntryFailure: return yes == NativeEntryFailure and count != 0
  if no >= NativeEntryLimit: return false
  if yes == NativeEntryFailure: return item.branch.opcode in [1'u8, 40, 80]
  if yes >= NativeEntryLimit or item.branch.opcode notin {81'u8..90, 170..175}: return false
  if item.branch.opcode <= 90:
    # Immediate predicates use the same full-width sign extension as checked dispatch.
    let low = uint32(item.branch.immediate and 0xffffffff'u64)
    if cast[uint64](int64(cast[int32](low))) != item.branch.immediate: return false
  true

func fusionPathToken(state: NativeFusionContext, index: uint64): uint32 =
  ## Invalid or unlogged coordinates select no token, before any fixed-array access.
  if index >= state.visits or index >= uint64(NativeFusionVisitLimit): return 0
  uint32((state.path[int(index div 8)] shr (int(index and 7)*8)) and 255)

func fusionPathWord(path: NativeFusionPath, visits: uint64, index: int): uint64 =
  ## Ignore every byte after the returned prefix, including stale bytes in its last word.
  ## The caller has checked the visit bound and iterates only the used words.
  let tail = int(visits and 7)*8
  let words = int((visits+7) div 8)
  if index < 0 or index >= path.len or index >= words: return 0
  let value = path[index]
  if index == words-1 and tail != 0: value and ((1'u64 shl tail)-1) else: value

func sameFusionPath(left, right: NativeFusionPath, visits: uint64): bool =
  ## Full used-word equality authorizes a cache key; the hash alone grants no proof.
  for index in 0..<int((visits+7) div 8):
    if fusionPathWord(left, visits, index) != fusionPathWord(right, visits, index): return false
  true

func nativeFusionExit*(blocks: openArray[NativeFusionBlock], entry, next: uint32,
    gas, quota: uint64, state: NativeFusionContext): NativeFusionExit =
  ## Consume the exact bounded path backwards, checking every reservation and permitted edge.
  ## Last-predicate validation uses the committed register file at the frame bridge.
  result = default(NativeFusionExit)
  if state.paid > 1 or state.visits > uint64(NativeFusionVisitLimit) or
      state.gas > gas or state.remaining > quota or
      quota-state.remaining > uint64(NativeFusionVisitLimit)*uint64(NativeReadFactLimit):
    return
  if state.visits == 0:
    result.valid = state.paid == 0 and next == entry and state.gas == gas and state.remaining == quota
    return
  var successor = next
  var leftGas = gas
  var leftQuota = quota
  var last = true
  var completePath = false
  var lastToken = 0'u32
  var visits = state.visits
  while visits != 0:
    # A zero token anywhere in the logged prefix is invalid. Rank slots are one-based.
    dec visits
    let token = fusionPathToken(state, visits)
    if token == 0 or uint64(token) > uint64(blocks.len): return
    # Carry the proved final source identity to the bridge instead of decoding the path again.
    if last: lastToken = token
    let item {.cursor.} = blocks[int(token-1)]
    if item.span == 0 or item.span > NativeReadFactLimit or item.price > leftGas or uint64(
        item.span) > leftQuota: return
    leftGas -= item.price
    leftQuota -= uint64(item.span)
    if last and state.paid != 0:
      # An interior refusal names a certified memory guard. A paid terminal is
      # legal only when native lowering deliberately left the terminal checked.
      if next <= item.header or next > item.terminal: return
      if next == item.terminal:
        if item.targets[0] != NativeEntryFailure: return
      else:
        let position = next-item.header-1
        if position >= 32 or (item.guards and (1'u32 shl int(position))) == 0:
          return
      result.paidHeader = item.header+1
    else:
      if successor notin item.targets: return
      completePath = true
    successor = item.header
    last = false
  if successor != entry or leftGas != state.gas or leftQuota != state.remaining:
    return default(NativeFusionExit)
  result.valid = true
  result.lastToken = lastToken
  result.attempted = uint32(quota-leftQuota)
  result.branches = completePath

proc checkNativeFusionExit*(memo: var NativeFusionReceipts, blocks: openArray[NativeFusionBlock],
    entry, next: uint32, gas, quota: uint64, state: NativeFusionContext): NativeFusionExit =
  ## Only full used-prefix equality substitutes the source walk. Every used word participates
  ## in the bounded hash; live debits, count and exit mode must also match. The frame still
  ## checks the final predicate and paid source site. Unwritten tail bytes have no authority.
  if state.visits == 0 or state.visits > uint64(NativeFusionVisitLimit) or
      state.paid > 1 or state.gas > gas or state.remaining > quota:
    return nativeFusionExit(blocks, entry, next, gas, quota, state)
  let head = fusionPathWord(state.path, state.visits, 0)
  let short = state.visits <= 8
  var hash = ((uint64(next) shl 25) xor state.visits xor head)*0x9e3779b97f4a7c15'u64
  if not short:
    # The ordinary one-word path keeps one scalar hash; longer paths include every later word.
    for index in 1..<int((state.visits+7) div 8):
      hash = (hash xor fusionPathWord(state.path, state.visits, index))*0x9e3779b97f4a7c15'u64
  let index = int(hash shr 56)
  # Borrow the fixed cache slot; a value binding would copy the entire wider path on every hit.
  let candidate = addr memo[index]
  let paid = state.paid != 0
  if candidate.visits == state.visits and candidate.entry == entry and candidate.next == next and
      (candidate.receipt.paidHeader != 0) == paid and gas-state.gas == candidate.gas and
      quota-state.remaining == uint64(candidate.receipt.attempted):
    if short:
      # A proved short key stores its canonical head, excluding unwritten tail bytes.
      if candidate.path[0] == head: return candidate.receipt
    elif sameFusionPath(candidate.path, state.path, state.visits):
      return candidate.receipt
  result = nativeFusionExit(blocks, entry, next, gas, quota, state)
  if result.valid:
    # The full verifier alone authorizes a new cache entry; copying fixed words happens only here.
    memo[index] = NativeFusionReceipt(path: state.path, visits: state.visits,
      gas: gas-state.gas, entry: entry, next: next, receipt: result)
    if short: memo[index].path[0] = head
