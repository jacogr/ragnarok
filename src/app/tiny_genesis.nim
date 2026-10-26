# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit public-key Tiny development genesis. Six public deterministic signing identities are
## solely local testnet identities. Native codecs construct every global chapter before hashing.

import std/strutils
import ../chain/[genesis, parameters, presets]
import ../codec/[bounded, header, state_layout, state_trie, state_safrole, state_consensus,
  state_disputes, state_authorization, state_history, state_privileges, state_statistics,
  state_workqueues, state_outputs]
import ../crypto/primitives
import ../bandersnatch/bandersnatch
import ../state/store
import ../lib/json_writer

proc tinySigningKey*(index: range[0..5]): BsResult[BsKey] =
  ## Scalars1..6 are public development identities, never generated or loaded production secrets.
  var scalar = default(array[32, byte])
  scalar[0] = byte(index+1)
  importScalar(scalar)
proc tinyPeerKey*(index: range[0..5]): CryptoResult[EdPublicKey] =
  ## Ed25519 seeds16..21 match the loopback TLS certificates produced by the launcher.
  var seed = default(array[32, byte])
  seed[0] = byte(index+16)
  let imported = importSeed(seed)
  if imported.error != CryptoError.None:
    return CryptoResult[EdPublicKey]() # No identity is exposed on primitive refusal.
  publicKey(imported.value)
proc tinyParameters*(): ParameterResult =
  ## Select the canonical immutable Tiny tuple from the shared chain catalog.
  presetParameters(ChainPreset.Tiny)

proc initTinyGenesis*(): GenesisResult =
  ## Construct a complete empty-service map, fixed six-member ring and fallback first epoch.
  ## A configured genesis is a trust anchor; its zero seal is never treated as an authenticated child.
  let parameters = tinyParameters()
  if not parameters.ok: return invalidGenesis() # No default parameter tuple authorizes capture.
  var roster = newSeq[StateValidator](6)
  var members: seq[byte] = @[]
  for index in 0..<6:
    let key = tinySigningKey(index)
    let ed = tinyPeerKey(index)
    if key.error != BsError.None or ed.error != CryptoError.None: return invalidGenesis()
    let public = publicKey(key.value)
    if public.error != BsError.None: return invalidGenesis() # Invalid primitive outputs cannot become roster entries.
    roster[index] = StateValidator(bandersnatch: StateBsKey(array[32, byte](public.value)),
      ed25519: StateEdKey(array[32, byte](ed.value)))
    for octet in array[32, byte](public.value): members.add(octet)
  let setup = newSetup(6)
  if setup.error != BsError.None: return invalidGenesis() # Use the unchanged pinned SRS.
  let root = commitRing(setup.value, members)
  close(setup.value)
  if root.error != BsError.None: return invalidGenesis() # A failed commitment is not an all-zero root.
  let validatorPolicy = ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
    maxBytes: ByteLimit(2017))
  var schedule = newSeq[StateBsKey](12)
  for index in 0..<12: schedule[index] = roster[index mod 6].bandersnatch
  let consensus = safroleStateEntry(SafroleState(pending: roster,
    root: StateRingRoot(array[144, byte](root.value)), schedule: keySchedule(schedule),
    accumulator: @[]), SafroleStateConfig(validators: validatorPolicy, epochSlots: EpochSlots(12),
      maxAccumulator: ElementLimit(12), maxBytes: ByteLimit(10000)))
  if consensus.error != StateComponentError.None: return invalidGenesis()
  var entries = @[consensus.value, entropyEntry(default(StateEntropy)), timeEntry(StateTime(0))]
  for chapter in [ValidatorChapter.Staging, ValidatorChapter.Active, ValidatorChapter.Previous]:
    let encoded = validatorEntry(chapter, roster, validatorPolicy)
    if encoded.error != StateComponentError.None: return invalidGenesis()
    entries.add(encoded.value) # Each captured entry owns its exact ordered roster.
  for kind in [AuthorizationKind.Pools, AuthorizationKind.Queues]:
    var rows = newSeq[AuthorizerRow](2)
    if kind == AuthorizationKind.Queues:
      for core in 0..<2: rows[core] = newSeq[AuthorizerHash](
          80) # Fixed empty-code hash placeholders; no reports are submitted.
    let encoded = authorizationEntry(kind, rows, AuthorizationConfig(cores: CoreCount(2),
      maxHashes: ElementLimit(160), maxBytes: ByteLimit(5120)))
    if encoded.error != AuthorizationError.None: return invalidGenesis()
    entries.add(encoded.value)
  let headerPolicy = HeaderConfig(cores: CoreCount(2), authorValidators: ValidatorCount(6),
    epochSlots: EpochSlots(12), maxBytes: ByteLimit(4096))
  let initial = header.Header(unsigned: UnsignedHeader(epoch: absentEpoch(), winners: absentWinners(),
    slot: HeaderSlot(0), offenders: @[]))
  var wire = newSeq[byte](4096)
  let encodedHeader = encodeHeader(initial, headerPolicy, wire)
  if encodedHeader.error != HeaderError.None: return invalidGenesis()
  wire.setLen(encodedHeader.value)
  let hash = blake2b256(wire)
  if hash.error != CryptoError.None: return invalidGenesis()
  let history = historyStateEntry(HistoryState(blocks: @[HistoryBlock(
    header: HistoryHeaderHash(array[32, byte](hash.value)), slot: HistorySlot(0), packages: @[])],
    peaks: @[]), HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8),
      perBlock: ElementLimit(0), totalPackages: ElementLimit(0), peaks: ElementLimit(64),
      maxBytes: ByteLimit(4096)))
  if history.error != HistoryError.None: return invalidGenesis()
  entries.add(history.value)
  let judgments = disputeStateEntry(DisputeState(), DisputeStateConfig(perSet: ElementLimit(0),
    totalItems: ElementLimit(0), maxBytes: ByteLimit(4)))
  if judgments.error != DisputeStateError.None: return invalidGenesis()
  entries.add(judgments.value)
  entries.add(StateEntry(key: chapterKey(StateChapter(10)), value: @[0'u8,
      0])) # Two canonical absent core assignments.
  let privileges = privilegeStateEntry(PrivilegeState(assigners: newSeq[ServiceIndex](2), always: @[]),
    PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(0), maxBytes: ByteLimit(21)))
  if privileges.error != PrivilegeError.None: return invalidGenesis()
  entries.add(privileges.value)
  let activity = activityStateEntry(ActivityState(validators: [newSeq[ValidatorActivity](6),
    newSeq[ValidatorActivity](6)], cores: newSeq[CoreActivity](2), services: @[]),
    ActivityConfig(cores: CoreCount(2), current: ValidatorCount(6), previous: ValidatorCount(6),
      maxServices: ElementLimit(0), maxBytes: ByteLimit(1000)))
  if activity.error != ActivityError.None: return invalidGenesis()
  entries.add(activity.value)
  let queues = WorkQueueConfig(epochSlots: EpochSlots(12), cores: CoreCount(2),
    maxBytes: ByteLimit(12))
  let ready = readyStateEntry(newSeq[ReadyRow](12), queues)
  let accumulated = accumulatedStateEntry(newSeq[AccumulatedRow](12), queues)
  let outputs = outputLogEntry([], OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(1)))
  if ready.error != WorkQueueError.None or accumulated.error != WorkQueueError.None or
      outputs.error != OutputLogError.None: return invalidGenesis()
  entries.add(ready.value)
  entries.add(accumulated.value)
  entries.add(outputs.value)
  captureBlockSnapshot(wire, entries, parameters.value, genesisStoreLimits())

proc hex*(bytes: openArray[byte]): string =
  ## Canonical lowercase diagnostics/configuration encoding retains every complete octet.
  result = ""
  for octet in bytes: result.add(toHex(int(octet), 2).toLowerAscii())
proc tinyChainText*(parent: BlockSnapshot): string =
  ## Emit the existing strict chain configuration, including every complete-map entry and header.
  var wire = newSeq[byte](parent.header.headerInfo.value.consumed)
  discard parent.header.encodeOwnedHeader(wire)
  let state = parent.stateSnapshot
  var entries = JsonObject()
  for index in 0..<state.commitment.entries:
    let key = state.keyAt(StateEntryIndex(index)).value
    entries.add(hex(array[31, byte](key)), json(hex(state.lookup(key).value.bytes)))
  $jsonObject([("protocol_parameters", json(hex(parent.chainParameters.encodeParameters))),
    ("genesis_header", json(hex(wire))), ("genesis_state", json(entries))])
