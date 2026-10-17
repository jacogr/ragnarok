## GP 0.8.0 safrole.tex, The Extrinsic and Tickets: authenticate and admit a complete ticket batch.
## Input C(4) already has posterior pending/root; entropy2 is posterior entropy[2]. No store writes or schedules.
import ../codec/[state_safrole, state_consensus, tickets, bounded, assurances]
import ../bandersnatch/bandersnatch

type
  ## Protocol epoch/tail/block parameters and explicit finite chapter/accumulator resource ceilings.
  TicketAdmissionConfig* = object
    state*: SafroleStateConfig
    tailStart*: EpochSlots
    blockTickets*: TicketLimit
  ## Default/failure alternatives expose no candidate accumulator, snapshot or partial accepted prefix.
  TicketAdmissionError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidSlot, InvalidState, LimitExceeded, LengthOverflow,
      UnexpectedTicket, InvalidAttempt, InvalidProof, BadOrder, Duplicate, NotRetained,
        BackendFailure, MissingState
  ## Only complete success contains the private immutable candidate C(4) owner.
  TicketAdmissionResult* = object
    case status: TicketAdmissionError
    of None:
      completed: SafroleStateSnapshot # Snapshot retains copied fields without retaining borrowed input/proof bytes.
    else:
      discard # Rejected batches publish only their reason.

## Read only a reason without exposing or retagging candidate state.
func error*(outcome: TicketAdmissionResult): TicketAdmissionError = outcome.status
## Extract an immutable candidate only after checking successful batch admission.
func value*(outcome: TicketAdmissionResult): SafroleStateSnapshot {.inline,
    requires: outcome.status == TicketAdmissionError.None.} = outcome.completed

## Preserve codec configuration/extent policy failures; other errors denote malformed C(4).
func codecError(reason: StateComponentError): TicketAdmissionError =
  case reason
  of StateComponentError.InvalidConfig: TicketAdmissionError.InvalidConfig # Explicit caller configuration failure.
  of StateComponentError.LimitExceeded: TicketAdmissionError.LimitExceeded # Independent local byte/count ceiling.
  of StateComponentError.LengthOverflow: TicketAdmissionError.LengthOverflow # No unchecked narrowing/allocation.
  else: TicketAdmissionError.InvalidState # Default/malformed state is never an empty accumulator.

## Compare identifier octets lexicographically; attempts never break identifier ties.
func compare(a, b: WinningTicketId): int =
  let left = array[32, byte](a)
  let right = array[32, byte](b)
  for i in 0..<32:
    if left[i] < right[i]: return -1 # First differing byte selects the lower score.
    if left[i] > right[i]: return 1 # Higher scores are evicted first at saturation.
  0 # Equality is a duplicate identifier even if attempts differ.

## Binary-search an already canonical accumulator without sorting or mutating its records.
func contains(values: openArray[WinningTicket], key: WinningTicketId): bool =
  var first = 0
  var last = values.len
  while first < last:
    let middle = first+(last-first) div 2 # Avoid adding two arbitrary native indices.
    let order = compare(key, values[middle].id)
    if order == 0: return true # Complete fixed identifier equality only.
    if order < 0:
      last = middle # Search strictly lower identifiers.
    else:
      first = middle+1 # Search strictly higher identifiers.
  false

## Borrow serialized C(4)/proofs synchronously and return a new immutable candidate on complete success.
## previous/target are parent/new slots, even if a caller already advanced working-state C(11).
## On crossing, reset accumulation once; duplicate exclusion still uses the supplied prior accumulator.
## Caller coordinates rotation/entropy first and publishes this candidate only after remaining block stages pass.
proc admitSafroleTickets*(input: openArray[byte], previous, target: StateTime,
    entropy2: StateEntropyWord, submitted: openArray[Ticket],
    config: TicketAdmissionConfig): TicketAdmissionResult =
  let epoch = uint64(config.state.epochSlots)
  let cores = uint64(config.state.validators.cores)
  if epoch == 0 or uint64(config.tailStart) == 0 or uint64(config.tailStart) >= epoch or
      cores < 2 or cores > 341:
    return TicketAdmissionResult(status: TicketAdmissionError.InvalidConfig) # No division by zero or unsupported SRS domain.
  if epoch > uint64(high(int) div sizeof(WinningTicket)) or epoch > high(uint64) div 2:
    return TicketAdmissionResult(status: TicketAdmissionError.LengthOverflow) # Prove accumulator native storage and twice-epoch arithmetic.
  if uint32(target) <= uint32(previous):
    return TicketAdmissionResult(status: TicketAdmissionError.InvalidSlot) # Slots neither repeat nor wrap/backtrack.
  if uint64(submitted.len) > uint64(config.blockTickets):
    return TicketAdmissionResult(status: TicketAdmissionError.LimitExceeded) # Reject count before copying/verifying proofs.
  if submitted.len > high(int) div sizeof(WinningTicket):
    return TicketAdmissionResult(status: TicketAdmissionError.LengthOverflow) # Bound temporary verified-output storage.
  if submitted.len != 0 and uint64(uint32(target)) mod epoch >= uint64(config.tailStart):
    return TicketAdmissionResult(status: TicketAdmissionError.UnexpectedTicket) # Tail slots admit only the empty extrinsic.
  if uint64(input.len) > uint64(config.state.maxBytes):
    return TicketAdmissionResult(status: TicketAdmissionError.LimitExceeded) # No copying of over-budget serialized state.
  let captured = decodeSafroleState(input, config.state)
  if captured.error != StateComponentError.None:
    return TicketAdmissionResult(status: codecError(
        captured.error)) # Codec validates every count/typed extent before allocation.
  if captured.value.consumed != input.len:
    return TicketAdmissionResult(status: TicketAdmissionError.InvalidState) # C(4) is an exact value, not a prefix.
  let owner = captured.value.snapshot
  let info = safroleInfo(owner).value
  var old = newSeq[WinningTicket](info.accumulated)
  for i in 0..<old.len:
    old[i] = accumulatedTicketAt(owner, SafroleStateIndex(uint64(
        i))).value # Copy fixed records through their owner.
    if i > 0 and compare(old[i-1].id, old[i].id) >= 0:
      return TicketAdmissionResult(status: TicketAdmissionError.InvalidState) # No implicit repair of an invalid prior contest.
  let population = uint64(info.validators) # The codec proves positive allowed pending population under the selected profile.
  let twice = epoch*2
  let attempts = twice div population + uint64(ord(twice mod population != 0))
  for ticket in submitted:
    if uint64(uint8(ticket.attempt)) >= attempts:
      return TicketAdmissionResult(status: TicketAdmissionError.InvalidAttempt) # ceil(2*epoch/pending), not a fixed attempts constant.
  var setup = default(BsSetup)
  if submitted.len != 0:
    let made = newSetup(int(cores*3)) # Chain profile keeps its domain when pending population resizes.
    if made.error != BsError.None:
      return TicketAdmissionResult(status: TicketAdmissionError.BackendFailure) # No accepted tickets after setup refusal.
    setup = made.value
  var incoming = newSeq[WinningTicket](submitted.len)
  var context = default(array[48, byte])
  for i, ch in "jam_ticket_seal":
    context[i] = byte(ch) # Exact 15-byte ASCII token; dollar-sign notation is not a token byte.
  let entropy = array[32, byte](entropy2)
  for i in 0..<32:
    context[15+i] = entropy[i] # Posterior entropy[2], not the accumulator, entropy[3] or a proof prefix.
  for i, ticket in submitted:
    context[47] = byte(ticket.attempt) # Exactly one E1 entry-index byte; no count prefix or terminator.
    let verified = verifyRing(setup, BsRingRoot(array[144, byte](info.root)),
      BsRingProof(array[784, byte](ticket.proof)), context, [])
    if verified.error != BsError.None:
      if verified.error in [BsError.InvalidEncoding, BsError.InvalidLength,
          BsError.VerificationFailure]:
        return TicketAdmissionResult(status: TicketAdmissionError.InvalidProof) # Malformed or non-verifying proof is invalid input.
      else:
        return TicketAdmissionResult(status: TicketAdmissionError.BackendFailure) # Backend/owner/panic errors are never invalid-proof success.
    incoming[i] = WinningTicket(id: WinningTicketId(array[32, byte](verified.value)),
        attempt: ticket.attempt)
    if i > 0 and compare(incoming[i-1].id, incoming[i].id) >= 0:
      return TicketAdmissionResult(status: TicketAdmissionError.BadOrder) # Strict identifier order rejects duplicates within the batch too.
    if contains(old, incoming[i].id):
      return TicketAdmissionResult(status: TicketAdmissionError.Duplicate) # Disjointness is by identifier, never full tuple/proof equality.
  let changed = uint64(uint32(target)) div epoch > uint64(uint32(previous)) div epoch
  let priorCount = if changed: 0 else: old.len # A multi-epoch skip resets once, preserving no obsolete contest entries.
  if incoming.len > high(int)-priorCount:
    return TicketAdmissionResult(status: TicketAdmissionError.LengthOverflow) # Prove union count before adding.
  let kept = min(int(epoch), priorCount+incoming.len)
  if uint64(kept) > uint64(config.state.maxAccumulator):
    return TicketAdmissionResult(status: TicketAdmissionError.LimitExceeded) # Local policy cannot silently truncate to less than an epoch.
  var selected = newSeq[WinningTicket](kept)
  var a = 0
  var b = 0
  for i in 0..<kept:
    if b < incoming.len and (a >= priorCount or compare(incoming[b].id, old[a].id) < 0):
      selected[i] = incoming[b] # Merge lower new identifier without sorting/reordering the submitted batch.
      inc b
    else:
      selected[i] = old[a] # Retain the lower old score; duplicates were already rejected.
      inc a
  if b != incoming.len:
    return TicketAdmissionResult(status: TicketAdmissionError.NotRetained) # Every submitted ticket must survive epoch-sized truncation.
  var source = SafroleState(pending: newSeq[StateValidator](info.validators), root: info.root,
    schedule: ticketSchedule(@[]), accumulator: selected)
  for i in 0..<source.pending.len:
    source.pending[i] = pendingValidatorAt(owner, StateValidatorIndex(uint64(
        i))).value # Preserve posterior roster exactly.
  case info.kind
  of SealerKind.Tickets:
    var tickets = newSeq[WinningTicket](info.slots) # Existing schedule remains unchanged by admission.
    for i in 0..<tickets.len:
      tickets[i] = sealerTicketAt(owner, SafroleStateIndex(uint64(i))).value
    source.schedule = ticketSchedule(tickets)
  of SealerKind.Keys:
    var keys = newSeq[StateBsKey](info.slots) # Preserve every fallback slot and duplicate key.
    for i in 0..<keys.len:
      keys[i] = sealerKeyAt(owner, SafroleStateIndex(uint64(i))).value
    source.schedule = keySchedule(keys)
  let encoded = safroleStateEntry(source, config.state)
  if encoded.error != StateComponentError.None:
    return TicketAdmissionResult(status: codecError(
        encoded.error)) # Complete posterior bytes must fit the caller's policy.
  let decoded = decodeSafroleState(encoded.value.value, config.state)
  if decoded.error != StateComponentError.None:
    return TicketAdmissionResult(status: codecError(decoded.error)) # No partial candidate if capture fails.
  TicketAdmissionResult(status: TicketAdmissionError.None, completed: decoded.value.snapshot)
