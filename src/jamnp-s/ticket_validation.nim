# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Detached finalized-epoch context and sealed network ticket verification retain no canonical graph or native key owner.
## Successful tickets are pending GP inputs; neither transport acknowledgment nor this proof check performs canonical adoption.
import std/assertions
import ./ticket_packet
import ../chain/[genesis, parameters]
import ../codec/[bounded, header, tickets, assurances]
import ../codec/state/[safrole, consensus, layout, trie]
import ../state/store
import ../bandersnatch/bandersnatch
import ../crypto/primitives

type
  NetworkTicketError* {.pure.} = enum ## Failed/default outcomes expose only reasons and actual failed child causes.
    Uninitialized, None, InvalidPacket, InvalidConfig, NoSource, InvalidState, InvalidEpoch,
    InvalidWindow, WrongRecipient, WrongProxy, AlreadyIncluded, LimitExceeded, Exhausted, NoSigner,
    StateFailure, RingFailure, HashFailure
  NetworkTicketResult*[T] = object ## Complete success or a genuine child failure selects exactly its private payload.
    case status: NetworkTicketError
    of None: completed: T
    of StateFailure: stateReason: StateComponentError
    of RingFailure: ringReason: BsError
    of HashFailure: hashReason: CryptoError
    else: discard # No accepted proof or default cryptographic cause exists on ordinary refusal.
  TicketSourceData = ref object ## Fresh decoded fixed metadata/rosters are independent from the complete source map.
    source: genesis.BlockHash
    posterior: StateRoot
    epoch, duration, tail, sourceSlot: uint32
    cores: int
    root: StateRingRoot
    entropy2: StateEntropyWord
    previous, current, pending: seq[StateEdKey]
    pendingBs: seq[StateBsKey]
    included: seq[WinningTicketId]
    fingerprint: array[32, byte]
  TicketSource* = object ## Only a selected finalized complete snapshot can construct this detached source owner.
    data: nil TicketSourceData
  TicketRecipient* = object ## Trusted host copies actual local/peer identities and observed time; no native pointer crosses the CPU boundary.
    local*, peer*: StateEdKey
    now*: StateTime
    connectivityEpoch*: uint32
    delivery*: TicketDelivery
  CheckedTicketData = ref object ## Private immutable proof/output facts contain no canonical snapshot, roster arrays or worker/native authority.
    packet: TicketPacket
    id: WinningTicketId
    proxy, local, peer: StateEdKey
    delivery: TicketDelivery
    distributionEpoch, duration: uint32
    context: array[32, byte]
    source: genesis.BlockHash
  CheckedNetworkTicket* = object ## Only the complete RingVRF/epoch/recipient verifier constructs an accepted pending ticket.
    data: nil CheckedTicketData
func error*[T](outcome: NetworkTicketResult[T]): NetworkTicketError =
  ## Inspect failure before any source or checked-ticket extraction.
  outcome.status
func value*[T](outcome: NetworkTicketResult[T]): T {.requires: outcome.status ==
    NetworkTicketError.None.} =
  ## Only complete verified success carries its owner.
  outcome.completed
func ticketFailure*[T](reason: NetworkTicketError): NetworkTicketResult[T] {.requires: reason notin
    [NetworkTicketError.None, NetworkTicketError.StateFailure, NetworkTicketError.RingFailure,
        NetworkTicketError.HashFailure].} =
  ## Ordinary lifecycle/capture failures cannot fabricate a child failure cause.
  NetworkTicketResult[T](status: reason)
func stateError*[T](outcome: NetworkTicketResult[T]): StateComponentError {.requires: outcome.status ==
    NetworkTicketError.StateFailure.} =
  ## Preserve the actual failed exact chapter decoder's cause.
  outcome.stateReason
func ringError*[T](outcome: NetworkTicketResult[T]): BsError {.requires: outcome.status ==
    NetworkTicketError.RingFailure.} =
  ## Invalid proof/encoding remains distinct from native backend/panic refusal.
  outcome.ringReason
func hashError*[T](outcome: NetworkTicketResult[T]): CryptoError {.requires: outcome.status ==
    NetworkTicketError.HashFailure.} =
  ## A source fingerprint failure cannot be mistaken for cryptographic ticket rejection.
  outcome.hashReason
func valid*(source: TicketSource): bool =
  ## Defaults confer no finalized epoch or ring commitment.
  source.data != nil
func valid*(ticket: CheckedNetworkTicket): bool =
  ## Raw proof bytes and default handles cannot enter a pending pool as verified tickets.
  ticket.data != nil
proc sourceData(source: TicketSource): TicketSourceData {.requires: source.valid.} =
  ## Bind private immutable storage before observing its fixed facts.
  let selected = source.data
  assert selected != nil
  selected
proc checkedData(ticket: CheckedNetworkTicket): CheckedTicketData {.requires: ticket.valid.} =
  ## Retained immutable proof facts never grant Native cancellation or CPU collection authority.
  let selected = ticket.data
  assert selected != nil
  selected
proc sourceBlock*(source: TicketSource): genesis.BlockHash {.requires: source.valid.} =
  ## Services compares both selected header identity and posterior state commitment before reuse.
  source.sourceData.source
proc stateRoot*(source: TicketSource): StateRoot {.requires: source.valid.} =
  ## A header hash alone cannot bind a caller-provided posterior state map.
  source.sourceData.posterior
proc epoch*(source: TicketSource): uint32 {.requires: source.valid.} =
  ## The finalized distribution epoch is separate from the packet's following use epoch.
  source.sourceData.epoch
proc epochLength*(source: TicketSource): uint32 {.requires: source.valid.} =
  ## Fixed bounded profile geometry supports host-only stale-epoch retirement.
  source.sourceData.duration
proc lotteryTail*(source: TicketSource): uint32 {.requires: source.valid.} =
  ## The source profile's GP ticket-admission cutoff remains separate from the earlier forwarding deadline.
  source.sourceData.tail
proc allowsTime*(source: TicketSource, now: StateTime, connectivityEpoch: uint32): bool =
  ## Fresh collection/retention checks cannot inherit an older job's epoch or admission window.
  if not source.valid: return false
  let selected = source.sourceData
  let epoch = uint32(now) div selected.duration
  if selected.sourceSlot > uint32(now) or selected.epoch != epoch or connectivityEpoch !=
      epoch: return false
  uint32(now) mod selected.duration < selected.tail
proc contextHash*(source: TicketSource): array[32, byte] {.requires: source.valid.} =
  ## Stable epoch/ring/entropy/role facts exclude the changing inclusion accumulator and finalized block identity.
  source.sourceData.fingerprint
proc packet*(ticket: CheckedNetworkTicket): TicketPacket {.requires: ticket.valid.} =
  ## Copy complete accepted proof bytes without exporting mutable backing storage.
  ticket.checkedData.packet
proc identifier*(ticket: CheckedNetworkTicket): WinningTicketId {.requires: ticket.valid.} =
  ## Identity is the full verified VRF output, not proof prefix or peer claim.
  ticket.checkedData.id
proc contextHash*(ticket: CheckedNetworkTicket): array[32, byte] {.requires: ticket.valid.} =
  ## Bind pool retention to the exact finalized epoch/ring/entropy/roster context.
  ticket.checkedData.context
proc distributionEpoch*(ticket: CheckedNetworkTicket): uint32 {.requires: ticket.valid.} =
  ## Host collection rechecks this epoch against freshly observed local time.
  ticket.checkedData.distributionEpoch
proc epochLength*(ticket: CheckedNetworkTicket): uint32 {.requires: ticket.valid.} =
  ## Retention never infers geometry from an untrusted packet.
  ticket.checkedData.duration
proc proxy*(ticket: CheckedNetworkTicket): StateEdKey {.requires: ticket.valid.} =
  ## This next-roster identity was selected from the verified full VRF output.
  ticket.checkedData.proxy
proc delivery*(ticket: CheckedNetworkTicket): TicketDelivery {.requires: ticket.valid.} =
  ## Accepted proxy ingress and distribution ingress retain their different forwarding contracts.
  ticket.checkedData.delivery
proc currentCount*(source: TicketSource): int {.requires: source.valid.} =
  ## Actual roster population, including vacant positions, controls distribution indexing.
  source.sourceData.current.len
proc pendingCount*(source: TicketSource): int {.requires: source.valid.} =
  ## Network proof/attempt bounds use actual next population, not maximum3*cores.
  source.sourceData.pending.len
proc networkAttempts*(source: TicketSource): int {.requires: source.valid.} =
  ## The pinned0/1 domain is further bounded by the GP ceiling for the actual next population.
  let selected = source.sourceData
  let twice = uint64(selected.duration)*2
  let ceiling = twice div uint64(selected.pending.len)+uint64(ord(twice mod uint64(
      selected.pending.len) != 0))
  int(min(2'u64, ceiling))
proc currentAt*(source: TicketSource, index: int): StateEdKey {.requires: source.valid and index >=
    0 and index < source.currentCount.} =
  ## Copy an owner-bound current-roster recipient without exposing mutable sequence storage.
  source.sourceData.current[index]
proc includedIdentifiers*(source: TicketSource): seq[WinningTicketId] {.requires: source.valid.} =
  ## Return a fresh bounded inclusion copy; callers never alias mutable storage or the worker-shared source owner.
  let selected = source.sourceData
  result = newSeq[WinningTicketId](selected.included.len)
  for index in 0..<result.len: result[index] = selected.included[index]
proc includes*(source: TicketSource, id: WinningTicketId): bool {.requires: source.valid.} =
  ## Sorted finalized accumulator lookup never widens to best-head or untrusted peer hints.
  let selected = source.sourceData
  let expected = array[32, byte](id)
  var first = 0
  var last = selected.included.len
  while first < last:
    let middle = first+(last-first) div 2
    let actual = array[32, byte](selected.included[middle])
    var order = 0
    for index in 0..<32:
      if expected[index] < actual[index]:
        order = -1
        break
      if expected[index] > actual[index]:
        order = 1
        break
    if order == 0: return true
    if order < 0: last = middle
    else: first = middle+1 # Strict sorted source preflight precedes binary search.
  false
proc sameKey(left, right: StateEdKey): bool =
  ## Identity comparison never confuses Ed25519 transport keys with proof-output or Bandersnatch domains.
  array[32, byte](left) == array[32, byte](right)
proc contains(keys: openArray[StateEdKey], key: StateEdKey): bool =
  ## Null identities confer no validator role even if an empty position appears in a roster.
  if sameKey(key, nullValidator().ed25519): return false
  for candidate in keys:
    if sameKey(candidate, key): return true
  false
proc roster(snapshot: BlockSnapshot, chapter: ValidatorChapter,
    limits: ValidatorStateConfig): NetworkTicketResult[seq[StateEdKey]] =
  ## Copy only complete exact bounded role identities, not metadata/native endpoints or a source map alias.
  let found = snapshot.lookup(chapterKey(StateChapter(ord(chapter))))
  if found.error != StateStoreError.None: return ticketFailure[seq[StateEdKey]](
      NetworkTicketError.NoSource)
  if uint64(found.value.byteLength) > uint64(limits.maxBytes):
    return ticketFailure[seq[StateEdKey]](NetworkTicketError.LimitExceeded)
  let wire = found.value.bytes
  let decoded = decodeStateValidators(wire, limits)
  if decoded.error != StateComponentError.None:
    return NetworkTicketResult[seq[StateEdKey]](status: NetworkTicketError.StateFailure,
        stateReason: decoded.error)
  if decoded.value.consumed != wire.len: return ticketFailure[seq[StateEdKey]](
      NetworkTicketError.InvalidState)
  let count = validatorCount(decoded.value.value).value
  var keys = newSeq[StateEdKey](count)
  for index in 0..<count: keys[index] = validatorAt(decoded.value.value, StateValidatorIndex(uint64(
      index))).value.ed25519
  NetworkTicketResult[seq[StateEdKey]](status: NetworkTicketError.None, completed: keys)
proc appendU32(wire: var seq[byte], value: uint32) =
  ## Local fingerprint encoding has one explicit width and no ABI-dependent object serialization.
  for index in 0..<4: wire.add(byte((value shr (index*8)) and 255))
proc captureTicketSource*(finalized: BlockSnapshotResult): NetworkTicketResult[TicketSource] =
  ## Caller selects actual canonical finality; all complete-map aliases retire before this detached source reaches a worker.
  if finalized.error != GenesisError.None: return ticketFailure[TicketSource](
      NetworkTicketError.NoSource)
  let snapshot = finalized.value
  if snapshot.fuzzSeedOnly: return ticketFailure[TicketSource](NetworkTicketError.NoSource)
  let profile = snapshot.chainParameters
  if not profile.valid: return ticketFailure[TicketSource](NetworkTicketError.InvalidConfig)
  let cores = profile.get(coreCount)
  let duration = profile.get(epochPeriod)
  let tail = profile.get(epochTailStart)
  if cores < 2 or cores > 341 or duration < 2 or duration > 4096 or tail == 0 or tail >= duration:
    return ticketFailure[TicketSource](NetworkTicketError.InvalidConfig)
  let limits = SafroleStateConfig(validators: ValidatorStateConfig(cores: CoreCount(cores),
      validators: ElementLimit(cores*3), maxBytes: ByteLimit(1024*1024)),
      epochSlots: EpochSlots(duration), maxAccumulator: ElementLimit(duration), maxBytes: ByteLimit(1024*1024))
  let found = snapshot.lookup(chapterKey(StateChapter(4)))
  if found.error != StateStoreError.None: return ticketFailure[TicketSource](
      NetworkTicketError.NoSource)
  if uint64(found.value.byteLength) > uint64(limits.maxBytes): return ticketFailure[TicketSource](
      NetworkTicketError.LimitExceeded)
  let wire = found.value.bytes
  let captured = decodeSafroleState(wire, limits)
  if captured.error != StateComponentError.None:
    return NetworkTicketResult[TicketSource](status: NetworkTicketError.StateFailure,
        stateReason: captured.error)
  if captured.value.consumed != wire.len: return ticketFailure[TicketSource](
      NetworkTicketError.InvalidState)
  let info = safroleInfo(captured.value.snapshot).value
  let rawEntropy = snapshot.lookup(chapterKey(StateChapter(6)))
  if rawEntropy.error != StateStoreError.None: return ticketFailure[TicketSource](
      NetworkTicketError.NoSource)
  if rawEntropy.value.byteLength != 128: return ticketFailure[TicketSource](
      NetworkTicketError.InvalidState)
  let entropy = decodeStateEntropy(rawEntropy.value.bytes)
  if entropy.error != StateComponentError.None:
    return NetworkTicketResult[TicketSource](status: NetworkTicketError.StateFailure,
        stateReason: entropy.error)
  let previous = roster(snapshot, ValidatorChapter.Previous, limits.validators)
  if previous.error != NetworkTicketError.None:
    if previous.error == NetworkTicketError.StateFailure:
      return NetworkTicketResult[TicketSource](status: NetworkTicketError.StateFailure,
          stateReason: previous.stateError)
    return ticketFailure[TicketSource](previous.error)
  let current = roster(snapshot, ValidatorChapter.Active, limits.validators)
  if current.error != NetworkTicketError.None:
    if current.error == NetworkTicketError.StateFailure:
      return NetworkTicketResult[TicketSource](status: NetworkTicketError.StateFailure,
          stateReason: current.stateError)
    return ticketFailure[TicketSource](current.error)
  var pending = newSeq[StateEdKey](info.validators)
  var pendingBs = newSeq[StateBsKey](info.validators)
  for index in 0..<pending.len:
    let record = pendingValidatorAt(captured.value.snapshot, StateValidatorIndex(uint64(index))).value
    pending[index] = record.ed25519
    pendingBs[index] = record.bandersnatch
  var included = newSeq[WinningTicketId](info.accumulated)
  for index in 0..<included.len:
    included[index] = accumulatedTicketAt(captured.value.snapshot, SafroleStateIndex(uint64(
        index))).value.id
    if index > 0:
      let left = array[32, byte](included[index-1])
      let right = array[32, byte](included[index])
      var less = false
      for position in 0..<32:
        if left[position] < right[position]:
          less = true
          break
        if left[position] > right[position]: break # Descending and duplicate source identifiers are both invalid state.
      if not less: return ticketFailure[TicketSource](NetworkTicketError.InvalidState)
  var identity: seq[byte] = @[]
  identity.appendU32(snapshot.slot div uint32(duration))
  identity.appendU32(uint32(duration))
  identity.appendU32(uint32(tail))
  identity.appendU32(uint32(cores))
  for octet in array[144, byte](info.root): identity.add(octet)
  for octet in array[32, byte](entropy.value.value[2]): identity.add(octet)
  for keys in [previous.value, current.value, pending]:
    identity.appendU32(uint32(keys.len))
    for key in keys:
      for octet in array[32, byte](key): identity.add(octet)
  for key in pendingBs:
    for octet in array[32, byte](key): identity.add(octet)
  let hashed = blake2b256(identity)
  if hashed.error != CryptoError.None:
    return NetworkTicketResult[TicketSource](status: NetworkTicketError.HashFailure,
        hashReason: hashed.error)
  let selected = TicketSourceData(source: snapshot.blockHash, posterior: snapshot.stateRoot,
      epoch: snapshot.slot div uint32(duration), duration: uint32(duration), tail: uint32(tail),
      sourceSlot: snapshot.slot, cores: int(cores), root: info.root, entropy2: entropy.value.value[2],
      previous: previous.value, current: current.value, pending: pending, pendingBs: pendingBs,
          included: included, fingerprint: array[32, byte](hashed.value))
  NetworkTicketResult[TicketSource](status: NetworkTicketError.None, completed: TicketSource(
      data: selected))
proc verifyNetworkTicket*(source: TicketSource, packet: TicketPacket,
    recipient: TicketRecipient): NetworkTicketResult[CheckedNetworkTicket] =
  ## A complete exact proof, current certainty/window and authenticated route contract precede all accepted output.
  if not source.valid: return ticketFailure[CheckedNetworkTicket](NetworkTicketError.NoSource)
  if not packet.valid: return ticketFailure[CheckedNetworkTicket](NetworkTicketError.InvalidPacket)
  let selected = source.sourceData
  let currentEpoch = uint32(recipient.now) div selected.duration
  if selected.sourceSlot > uint32(recipient.now) or selected.epoch != currentEpoch or
      recipient.connectivityEpoch != currentEpoch:
    return ticketFailure[CheckedNetworkTicket](NetworkTicketError.NoSource)
  if currentEpoch == high(uint32) or uint32(packet.epoch) == 0 or uint32(packet.epoch) !=
      currentEpoch+1:
    return ticketFailure[CheckedNetworkTicket](NetworkTicketError.InvalidEpoch)
  if uint32(recipient.now) mod selected.duration >= selected.tail:
    return ticketFailure[CheckedNetworkTicket](NetworkTicketError.InvalidWindow)
  let ticket = packet.ticket
  let twice = uint64(selected.duration)*2
  let attempts = twice div uint64(selected.pending.len)+uint64(ord(twice mod uint64(
      selected.pending.len) != 0))
  if uint64(uint8(ticket.attempt)) >= attempts:
    return ticketFailure[CheckedNetworkTicket](NetworkTicketError.InvalidPacket)
  case recipient.delivery
  of TicketDelivery.Proxy:
    let prior = contains(selected.previous, recipient.peer)
    let current = contains(selected.current, recipient.peer)
    let future = contains(selected.pending, recipient.peer)
    if not (prior or current or future):
      return ticketFailure[CheckedNetworkTicket](NetworkTicketError.WrongRecipient)
  of TicketDelivery.Distribution:
    if not contains(selected.current, recipient.local):
      return ticketFailure[CheckedNetworkTicket](NetworkTicketError.WrongRecipient)
  let setup = newSetup(selected.cores*3)
  if setup.error != BsError.None:
    return NetworkTicketResult[CheckedNetworkTicket](status: NetworkTicketError.RingFailure,
        ringReason: setup.error)
  var context = default(array[48, byte])
  for index, character in "jam_ticket_seal": context[index] = byte(character)
  let entropy = array[32, byte](selected.entropy2)
  for index in 0..<32: context[15+index] = entropy[index]
  context[47] = byte(ticket.attempt)
  let verified = verifyRing(setup.value, BsRingRoot(array[144, byte](selected.root)),
      BsRingProof(array[784, byte](ticket.proof)), context, [])
  if verified.error != BsError.None:
    return NetworkTicketResult[CheckedNetworkTicket](status: NetworkTicketError.RingFailure,
        ringReason: verified.error)
  let output = array[32, byte](verified.value)
  var selector = 0'u32
  for index in 28..<32: selector = (selector shl 8) or uint32(output[index])
  let index = int(uint64(selector) mod uint64(selected.pending.len))
  let proxy = selected.pending[index]
  case recipient.delivery
  of TicketDelivery.Proxy:
    if not sameKey(proxy, recipient.local): return ticketFailure[CheckedNetworkTicket](
        NetworkTicketError.WrongProxy)
  of TicketDelivery.Distribution:
    if not sameKey(proxy, recipient.peer): return ticketFailure[CheckedNetworkTicket](
        NetworkTicketError.WrongProxy)
  let identifier = WinningTicketId(output)
  if source.includes(identifier): return ticketFailure[CheckedNetworkTicket](
      NetworkTicketError.AlreadyIncluded)
  NetworkTicketResult[CheckedNetworkTicket](status: NetworkTicketError.None,
      completed: CheckedNetworkTicket(data: CheckedTicketData(packet: packet, id: identifier,
          proxy: proxy, local: recipient.local, peer: recipient.peer, delivery: recipient.delivery,
          distributionEpoch: selected.epoch, duration: selected.duration,
          context: selected.fingerprint,
          source: selected.source)))

proc produceNetworkTicket*(source: TicketSource, key: BsKey, local: StateEdKey,
    now: StateTime, connectivityEpoch: uint32, attempt: TicketAttempt): NetworkTicketResult[
        CheckedNetworkTicket] =
  ## Real registered-key signing is CPU-only; the resulting sealed proof binds its selected proxy rather than granting local canonical authority.
  if not source.allowsTime(now, connectivityEpoch):
    return ticketFailure[CheckedNetworkTicket](NetworkTicketError.NoSource)
  let selected = source.sourceData
  if selected.epoch == high(uint32): return ticketFailure[CheckedNetworkTicket](
      NetworkTicketError.InvalidEpoch)
  if uint8(attempt) > 1: return ticketFailure[CheckedNetworkTicket](
      NetworkTicketError.InvalidPacket)
  let twice = uint64(selected.duration)*2
  let attempts = twice div uint64(selected.pending.len)+uint64(ord(twice mod uint64(
      selected.pending.len) != 0))
  if uint64(uint8(attempt)) >= attempts:
    return ticketFailure[CheckedNetworkTicket](NetworkTicketError.InvalidPacket)
  let public = publicKey(key)
  if public.error != BsError.None:
    return NetworkTicketResult[CheckedNetworkTicket](status: NetworkTicketError.RingFailure,
        ringReason: public.error)
  let publicBytes = array[32, byte](public.value)
  var signer = -1
  for index in 0..<selected.pending.len:
    let sameIdentity = sameKey(selected.pending[index], local)
    let samePublic = array[32, byte](selected.pendingBs[index]) == publicBytes
    if sameIdentity and samePublic:
      signer = index
      break # An arbitrary TLS identity or unrelated private key cannot sign for a registered position.
  if signer < 0: return ticketFailure[CheckedNetworkTicket](NetworkTicketError.WrongRecipient)
  assert selected.pendingBs.len > 0 and selected.pendingBs.len <= 1023
  var members = newSeq[byte](selected.pendingBs.len*32)
  for index in 0..<selected.pendingBs.len:
    let member = array[32, byte](selected.pendingBs[index])
    for octet in 0..<32: members[index*32+octet] = member[octet]
  let setup = newSetup(selected.cores*3)
  if setup.error != BsError.None:
    return NetworkTicketResult[CheckedNetworkTicket](status: NetworkTicketError.RingFailure,
        ringReason: setup.error)
  var context = default(array[48, byte])
  for index, character in "jam_ticket_seal": context[index] = byte(character)
  let entropy = array[32, byte](selected.entropy2)
  for index in 0..<32: context[15+index] = entropy[index]
  context[47] = byte(attempt)
  let signed = signRing(setup.value, key, signer, members, context, [])
  if signed.error != BsError.None:
    return NetworkTicketResult[CheckedNetworkTicket](status: NetworkTicketError.RingFailure,
        ringReason: signed.error)
  let verified = verifyRing(setup.value, BsRingRoot(array[144, byte](selected.root)), signed.value,
      context, [])
  if verified.error != BsError.None:
    return NetworkTicketResult[CheckedNetworkTicket](status: NetworkTicketError.RingFailure,
        ringReason: verified.error)
  let output = array[32, byte](verified.value)
  var selector = 0'u32
  for index in 28..<32: selector = (selector shl 8) or uint32(output[index])
  let proxy = selected.pending[int(uint64(selector) mod uint64(selected.pending.len))]
  let packet = ticketPacket(TicketEpoch(selected.epoch+1), Ticket(attempt: attempt,
      proof: TicketProof(array[784, byte](signed.value))))
  assert packet.error == TicketPacketError.None
  verifyNetworkTicket(source, packet.value, TicketRecipient(local: proxy, peer: local, now: now,
      connectivityEpoch: connectivityEpoch, delivery: TicketDelivery.Proxy))
