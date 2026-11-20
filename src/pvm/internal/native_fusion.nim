# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Source-bound control flow for a bounded native graph. Up to 255 ranked source
## blocks share one optional arena, bounded by 256 KiB of published code and 4 KiB per entry.
## The source-header map has 512 slots so even the largest graph stays below half-full.
## The block cap bounds copied source IR independently of guest iteration counts. Original block
## prices and source attempts remain independent. Lowering can link only positive checked successors.
## Each native entry commits a bounded number of original reservations and returns their order.
## Ordinary graphs append one byte per visit to fixed call-local word storage; the returned count
## bounds every read. Unwritten tail bytes need no clearing and never participate in a receipt key.
## The checked bridge verifies this receipt before exposing a successor or resuming a paid
## memory operation. A segment may reuse validation of the same immutable source path.
## Dynamic edges require the frame's checked original-table tag and an immutable per-image
## target entry. Small deterministic SCCs retain only a visit count, bounded by 4096
## reservations per entry. The copied source order and count prove weighted debits.
## Up to eight members can use a compact entry. Every side edge returns to checked dispatch.
## The last reserved block may also return at one of its certified memory guards; the
## checked stream owns the unattempted suffix and the original fault or continuation.
## Scalar components keep first use of the compact-entry budget. No executable pointer escapes the arena.
## The target table counts toward the same image bound; cache storage remains frame-owned.

import ./[dynamic_jump_cache, jit_rules, native_ir, native_mixed_loop, native_read_body]

const
  NativeFusionTrainingFloor* = 524288'u64                   ## Prior settled attempts before a sampling segment.
  NativeFusionBlockLimit* = 255 ## One ranked graph; one-based byte tokens exclude zero.
  NativeFusionSlotLimit* = 512 ## Keep the largest byte-token graph below half-full in the checked map.
  NativeFusionVisitLimit* = 64 ## Fixed entry horizon, independent of the graph's block cap.
  NativeFusionCycleLimit* = 8 ## Bound source-cycle analysis and compact receipt validation.
  NativeFusionCycleVisitLimit* = 4096 ## Bound compact work per entry, including zero-priced cycles.
  NativeFusionReceiptBits = 11 ## Fixed one-probe cache geometry; a bucket never grants path authority.
  NativeFusionPathWords* = (NativeFusionVisitLimit+7) div 8 ## Fixed ordered byte-log storage.
  NativeFusionImageLimit* = 256*1024 ## Published graph bytes, including every entry and alignment padding.
  NativeFusionGasOffset* = NativeMixedLoopContextBytes
  NativeFusionQuotaOffset* = NativeFusionGasOffset+8
  NativeFusionPathOffset* = NativeFusionQuotaOffset+8
  NativeFusionVisitsOffset* = NativeFusionPathOffset+NativeFusionPathWords*8
  NativeFusionPaidOffset* = NativeFusionVisitsOffset+8
  NativeFusionJumpsOffset* = NativeFusionPaidOffset+8
  NativeFusionAddressOffset* = NativeFusionJumpsOffset+8
  NativeFusionTableBytes* = NativeFusionSlotLimit*8

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
    ## [false, true]; dynamic branches carry no static targets and use original-table entry permission.
    ## Other missing first targets leave the terminal to checked execution.
    header*, terminal*, first*, span*: uint32
    price*: uint64
    targets*: array[2, uint32]
    branch*: NativeOperation
    operations*: array[int(NativeReadFactLimit)-1, NativeOperation]
    guards*: uint32 ## Only these body nodes can be returned as paid refusals.
    cycleNext*, cycleSize*: uint8
      ## Certified simple SCC. Zero selects ordered path receipts. A compact paid return names
      ## a certified guard in the last reserved block.
    indirectEntry*: bool ## Cold proof that this header belongs to the original admitted jump table.
  NativeFusionContext* = object
    ## Call-local descriptors and ledger precede a fixed byte log and its returned count.
    ## Each native entry overwrites only its used prefix; unused bytes have no receipt authority.
    ## A paid lookup miss can retain an attempted address; only a completed final indirect edge
    ## makes address evidence for final live-jump validation.
    memory*: NativeMixedLoopContext
    gas*, remaining*: uint64
    path*: NativeFusionPath
    visits*, paid*: uint64
    jumps*: nil ptr DynamicJumpTags ## Frame-owned checked tags; borrowed only during native entry.
    address*: uint64 ## Wrapped pre-write address; meaningful only for a completed final indirect edge.
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
  NativeFusionReceipts* = array[1 shl NativeFusionReceiptBits, NativeFusionReceipt]
    ## One bounded 208 KiB call-local cache of successful proofs for exactly one borrowed graph.
    ## Its 2048 records reduce repeated source walks across diverse long paths while retaining one lookup.
    ## Only an active graph segment initializes this storage; no invocation borrow escapes it.

func nativeFusionSlot*(token: uint32): int {.inline.} =
  ## A one-based source-header token hashes into the fixed 512-slot, at-most-half-full map.
  ## Zero can be hashed but never confers source or entry authority.
  int((token*0x9e3779b9'u32) shr 23)

func indirect*(item: NativeFusionBlock): bool {.inline.} =
  ## Only original dynamic jump terminals use the guarded immutable native target map.
  item.branch.opcode in [50'u8, 180]

func indirectDelta*(item: NativeFusionBlock): uint32 {.inline.} =
  ## Dynamic load-and-jump packs its independent32-bit displacement above its loaded value.
  if item.branch.opcode == 180: uint32(item.branch.immediate shr 32)
  else: uint32(item.branch.immediate and 0xffffffff'u64)

func indirectValue*(item: NativeFusionBlock): uint64 {.inline.} =
  ## The original load literal sign-extends its low32 bits before any guest publication.
  cast[uint64](int64(cast[int32](uint32(item.branch.immediate and 0xffffffff'u64))))

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
  if item.indirect:
    # Guard misses deliberately leave the original terminal paid and checked, even with an empty body.
    if no != NativeEntryFailure or yes != NativeEntryFailure: return false
    return item.branch.opcode == 180 or item.branch.immediate == item.indirectValue
  if no == NativeEntryFailure: return yes == NativeEntryFailure and count != 0
  if no >= NativeEntryLimit: return false
  if yes == NativeEntryFailure: return item.branch.opcode in [1'u8, 40, 80]
  if yes >= NativeEntryLimit or item.branch.opcode notin {81'u8..90, 170..175}: return false
  if item.branch.opcode <= 90:
    # Immediate predicates use the same full-width sign extension as checked dispatch.
    let low = uint32(item.branch.immediate and 0xffffffff'u64)
    if cast[uint64](int64(cast[int32](low))) != item.branch.immediate: return false
  true

type
  NativeFusionCycle* = object
    ## One-based next token and member count certify one deterministic cyclic source order.
    next*, size*: uint8
    guarded*: bool ## Each member carries its component's memory-guard classification.
  NativeFusionCycles* = array[NativeFusionBlockLimit, NativeFusionCycle]
    ## Fixed cold analysis output; no program, frame, executable or invocation borrows.

func collectFusionCycles(blocks: openArray[NativeFusionBlock],
    complete: array[NativeFusionBlockLimit, bool], cycles: var NativeFusionCycles,
    allowGuards: bool) =
  ## Use at most eight members with exactly one distinct in-component successor per member.
  ## Fixed bit rows bound transitive closure to 255 squared times four word unions.
  var eligible = default(array[NativeFusionBlockLimit, bool])
  var reach = default(array[NativeFusionBlockLimit, array[4, uint64]])
  for index in 0..<blocks.len:
    # Earlier scalar components remain independent even if a memory edge connects back to them.
    eligible[index] = complete[index] and cycles[index].size == 0 and
      (allowGuards or blocks[index].guards == 0)
  for index in 0..<blocks.len:
    if not eligible[index]: continue
    for target in blocks[index].targets:
      for other in 0..<blocks.len:
        if eligible[other] and blocks[other].header == target:
          reach[index][other div 64] = reach[index][other div 64] or (1'u64 shl (other mod 64))
  for middle in 0..<blocks.len:
    # A row joins only a reachable source row; no allocation or recursive guest-sized walk.
    for first in 0..<blocks.len:
      if (reach[first][middle div 64] and (1'u64 shl (middle mod 64))) != 0:
        for word in 0..<4: reach[first][word] = reach[first][word] or reach[middle][word]
  var seen = default(array[NativeFusionBlockLimit, bool])
  for first in 0..<blocks.len:
    if seen[first] or (reach[first][first div 64] and (1'u64 shl (first mod 64))) == 0: continue
    var members = default(array[NativeFusionBlockLimit, bool])
    var count = 0
    var guarded = false
    for other in 0..<blocks.len:
      # Mutual reachability defines the entire SCC; a smaller cycle inside a branching SCC is refused.
      if (reach[first][other div 64] and (1'u64 shl (other mod 64))) != 0 and
          (reach[other][first div 64] and (1'u64 shl (first mod 64))) != 0:
        members[other] = true
        seen[other] = true
        inc count
        guarded = guarded or blocks[other].guards != 0
    if count > NativeFusionCycleLimit or (allowGuards and not guarded): continue
    var next = default(array[NativeFusionBlockLimit, uint8])
    var valid = true
    for index in 0..<blocks.len:
      if not members[index]: continue
      for target in blocks[index].targets:
        for other in 0..<blocks.len:
          if members[other] and blocks[other].header == target:
            if next[index] != 0 and next[index] != uint8(other+1): valid = false
            next[index] = uint8(other+1)
      if next[index] == 0: valid = false
    if not valid: continue
    for index in 0..<blocks.len:
      if members[index]:
        cycles[index] = NativeFusionCycle(next: next[index], size: uint8(count), guarded: guarded)

func nativeFusionCycles*(blocks: openArray[NativeFusionBlock]): NativeFusionCycles =
  ## Certify the original scalar components first, then consider remaining guarded cycles.
  ## Side edges leave compact execution, including any edge into another compact component.
  result = default(NativeFusionCycles)
  if blocks.len == 0 or blocks.len > NativeFusionBlockLimit: return
  var complete = default(array[NativeFusionBlockLimit, bool])
  var hasGuard = false
  for index in 0..<blocks.len:
    let item {.cursor.} = blocks[index]
    complete[index] = item.complete and not item.indirect and item.targets[0] != NativeEntryFailure
    hasGuard = hasGuard or (complete[index] and item.guards != 0)
    for earlier in 0..<index:
      if blocks[earlier].header == item.header: return
  collectFusionCycles(blocks, complete, result, allowGuards = false)
  if hasGuard: collectFusionCycles(blocks, complete, result, allowGuards = true)

proc markNativeFusionCycles*(blocks: var seq[NativeFusionBlock]) =
  ## Replace candidate annotations from complete copied source geometry. Refused SCCs stay ordinary.
  let cycles = nativeFusionCycles(blocks)
  for index in 0..<blocks.len:
    if index >= NativeFusionBlockLimit: return
    blocks[index].cycleNext = cycles[index].next
    blocks[index].cycleSize = cycles[index].size

func validFusionPaidExit(item: NativeFusionBlock, next: uint32): bool {.inline.} =
  ## A paid return names the original guard or an explicitly delegated terminal.
  if next <= item.header or next > item.terminal: return false
  if next == item.terminal: return item.targets[0] == NativeEntryFailure
  let position = next-item.header-1
  position < 32 and (item.guards and (1'u32 shl int(position))) != 0

func nativeFusionCycleExit*(blocks: openArray[NativeFusionBlock], entryToken, next: uint32,
    gas, quota: uint64, state: NativeFusionContext): NativeFusionExit =
  ## Certify every reservation along the unique in-cycle order from the original entry.
  ## A paid guard belongs to the last reserved block. Earlier visits completed their branches.
  ## On an unpaid return the bridge still validates the final live predicate before commit.
  ## Division before multiplication proves exact weighted gas and attempt debits.
  result = default(NativeFusionExit)
  if entryToken == 0 or uint64(entryToken) > uint64(blocks.len) or state.paid > 1 or
      state.visits > uint64(NativeFusionCycleVisitLimit) or state.gas > gas or state.remaining > quota:
    return
  let size = uint32(blocks[int(entryToken-1)].cycleSize)
  if size == 0 or size > uint32(NativeFusionCycleLimit): return
  let rounds = state.visits div uint64(size)
  let tail = uint32(state.visits mod uint64(size))
  var token = entryToken
  var nextToken = entryToken
  var lastToken = 0'u32
  var spent = gas-state.gas
  var attempts = quota-state.remaining
  if attempts > uint64(NativeFusionCycleVisitLimit)*uint64(NativeReadFactLimit): return
  for distance in 0..<int(size):
    # Every token stays within the copied graph and closes at exactly the certified member count.
    if token == 0 or uint64(token) > uint64(blocks.len) or (distance != 0 and token ==
        entryToken): return
    let item {.cursor.} = blocks[int(token-1)]
    if uint32(item.cycleSize) != size or item.cycleNext == 0 or item.indirect or
        item.span == 0 or item.span > NativeReadFactLimit: return
    let following = uint32(item.cycleNext)
    if uint64(following) > uint64(blocks.len) or blocks[int(following-1)].header notin
        item.targets: return
    let visits = rounds+uint64(ord(uint32(distance) < tail))
    if visits > attempts div uint64(item.span) or (item.price != 0 and visits >
        spent div item.price): return
    attempts -= visits*uint64(item.span)
    spent -= visits*item.price
    if uint32(distance) == tail: nextToken = token
    if uint32(distance) == (tail+size-1) mod size: lastToken = token
    token = following
  if token != entryToken or spent != 0 or attempts != 0: return
  let following {.cursor.} = blocks[int(nextToken-1)]
  if state.visits == 0:
    result.valid = state.paid == 0 and next == following.header and (state.gas < following.price or
      state.remaining < uint64(following.span))
    return
  let last {.cursor.} = blocks[int(lastToken-1)]
  if state.paid != 0:
    if next == last.terminal or not validFusionPaidExit(last, next): return
    return NativeFusionExit(valid: true, branches: state.visits > 1, lastToken: lastToken,
      attempted: uint32(quota-state.remaining), paidHeader: last.header+1)
  if next notin last.targets: return
  if next == following.header and state.visits != uint64(NativeFusionCycleVisitLimit) and
      state.gas >= following.price and state.remaining >= uint64(following.span): return
  result = NativeFusionExit(valid: true, branches: true, lastToken: lastToken,
    attempted: uint32(quota-state.remaining))

func fusionPathToken(state: NativeFusionContext, index: uint64): uint32 =
  ## Invalid or unlogged coordinates select no token, before any fixed-array access.
  if index >= state.visits or index >= uint64(NativeFusionVisitLimit): return 0
  uint32((state.path[int(index div 8)] shr (int(index and 7)*8)) and 255)

func sameFusionPrefix(left, right: NativeFusionPath, last: int): bool =
  ## The caller compares the sealed last word separately. Earlier words are entirely written.
  for index in 0..<last:
    if left[index] != right[index]: return false
  true

func nativeFusionExit*(blocks: openArray[NativeFusionBlock], entry, next: uint32,
    gas, quota: uint64, state: NativeFusionContext): NativeFusionExit =
  ## Consume the exact bounded path backwards, checking every reservation and permitted edge.
  ## A valid dynamic receipt proves reservations, the source path and original-table entry permission.
  ## Before committing state, the caller must validate the final live jump tag, captured pre-write
  ## address and any load result. Final-predicate validation also belongs to the frame bridge.
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
  var indirectSuccessor = false
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
      if not validFusionPaidExit(item, next): return
      result.paidHeader = item.header+1
    else:
      if item.indirect:
        if last:
          # Only a completed final dynamic edge needs a successor lookup; interior tokens already prove it.
          for candidate in blocks:
            if candidate.header == next:
              indirectSuccessor = candidate.indirectEntry
              break
        if not indirectSuccessor: return
      elif successor notin item.targets: return
      completePath = true
    successor = item.header
    indirectSuccessor = item.indirectEntry
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
  ## in the bounded hash; live debits, count and exit mode must also match. A valid cached dynamic
  ## receipt proves reservations, the source path and original-table entry permission. On every
  ## completed final indirect edge, the caller must recheck the live jump tag, captured pre-write
  ## address and any load result before committing state, including on cache hits. The caller also
  ## checks the final predicate and paid source site. Unwritten tail bytes have no authority.
  if state.visits == 0 or state.visits > uint64(NativeFusionVisitLimit) or
      state.paid > 1 or state.gas > gas or state.remaining > quota:
    return nativeFusionExit(blocks, entry, next, gas, quota, state)
  # The nonzero visit bound proves the occupied word index. Only that word can
  # contain unwritten bytes, so hash it and compare it using the same single mask.
  let lastVisit = state.visits-1
  let lastWord = int(lastVisit shr 3)
  let tail = state.path[lastWord] and (high(uint64) shr int((7-(lastVisit and 7))*8))
  let head = if lastWord == 0: tail else: state.path[0]
  var hash = ((uint64(next) shl 25) xor state.visits xor head)*0x9e3779b97f4a7c15'u64
  if lastWord != 0:
    # A longer path hashes every completely written middle word and its masked tail.
    for index in 1..<lastWord:
      hash = (hash xor state.path[index])*0x9e3779b97f4a7c15'u64
    hash = (hash xor tail)*0x9e3779b97f4a7c15'u64
  let index = int(hash shr (64-NativeFusionReceiptBits))
  # Borrow the fixed cache slot; a value binding would copy the entire wider path on every hit.
  let candidate = addr memo[index]
  let paid = state.paid != 0
  if candidate.visits == state.visits and candidate.entry == entry and candidate.next == next and
      (candidate.receipt.paidHeader != 0) == paid and gas-state.gas == candidate.gas and
      quota-state.remaining == uint64(candidate.receipt.attempted) and
      candidate.path[lastWord] == tail and
      (lastWord == 0 or sameFusionPrefix(candidate.path, state.path, lastWord)):
    return candidate.receipt
  result = nativeFusionExit(blocks, entry, next, gas, quota, state)
  if result.valid:
    # The full verifier alone authorizes a new cache entry; copying fixed words happens only here.
    memo[index] = NativeFusionReceipt(path: state.path, visits: state.visits,
      gas: gas-state.gas, entry: entry, next: next, receipt: result)
    memo[index].path[lastWord] = tail
