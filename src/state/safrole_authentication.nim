## GP 0.8.0 safrole.tex ticketconditiontrue/ticketconditionfalse and vrfsigcheck.
## Authenticate a complete immutable header against supplied posterior schedule/active keys and parent history.
import ../codec/[state_safrole, state_consensus, header, bounded]
import ../bandersnatch/bandersnatch
import ./entropy

type
  ## Independent finite C(4)/roster and complete-header ceilings; epoch length selects the cyclic schedule slot.
  SafroleAuthConfig* = object
    state*: SafroleStateConfig
    maxHeaderBytes*: ByteLimit
  ## Failed/default authentication exposes neither entropy, a partial seal output nor a header witness.
  SafroleAuthError* {.pure.} = enum
    Uninitialized, None, MissingState, InvalidConfig, InvalidSlot, InvalidState, InvalidHeader,
    LimitExceeded, LengthOverflow, InvalidAuthor, InvalidSeal, InvalidTicket, InvalidEntropy, BackendFailure
  ## Successful copied metadata retains the exact immutable authenticated header and fixed verified outputs.
  SafroleAuthentication* = object
    header*: OwnedHeader
    entropy*: EntropyInput
    sealOutput*: BsOutput
    ticketed*: bool
  ## Private discriminator and payload require explicit success selection before application use.
  SafroleAuthResult* = object
    case status: SafroleAuthError
    of None:
      completed: SafroleAuthentication # No borrowed state pointers or native secret/setup owner survives.
    else:
      discard # Refusal contains its reason alone.

## Read the reason without allowing callers to manufacture success.
func error*(outcome: SafroleAuthResult): SafroleAuthError = outcome.status
## Extract verified entropy and its retained exact header only after both signatures and schedule binding pass.
func value*(outcome: SafroleAuthResult): SafroleAuthentication {.inline,
    requires: outcome.status == SafroleAuthError.None.} = outcome.completed

## Context adapters can preserve a failure reason, but cannot manufacture success without authenticated data.
func safroleAuthFailure*(reason: SafroleAuthError): SafroleAuthResult {.requires: reason !=
    SafroleAuthError.None.} =
  SafroleAuthResult(status: reason)

## Preserve policy/native extent errors while rejecting malformed serialized stage state.
func codecError(reason: StateComponentError): SafroleAuthError =
  case reason
  of StateComponentError.InvalidConfig: SafroleAuthError.InvalidConfig # Caller profile is not a chain definition.
  of StateComponentError.LimitExceeded: SafroleAuthError.LimitExceeded # Resource refusal is not an invalid signature.
  of StateComponentError.LengthOverflow: SafroleAuthError.LengthOverflow # No unchecked native extent narrowing.
  else: SafroleAuthError.InvalidState # Never fabricate default pending keys or a schedule.

## Distinguish contained native/backend refusal from invalid proof/key encodings or a false verification.
func proofError(reason: BsError, invalid: SafroleAuthError): SafroleAuthError =
  if reason in [BsError.BackendFailure, BsError.BackendPanic]:
    SafroleAuthError.BackendFailure # Contained primitive failure is not evidence that the submitted proof is invalid.
  else:
    invalid # A well-formed or malformed untrusted proof/key that does not verify cannot publish entropy.

## Use exact ASCII token bytes without a dollar, count, terminator or implicit prehash.
proc context(domain: string, seed: array[32, byte], ticketed: bool, attempt: byte): seq[byte] =
  result = newSeq[byte](domain.len+32+(if ticketed: 1 else: 0))
  for i, ch in domain: result[i] = byte(ch) # Copy only the literal token bytes.
  for i in 0..<32: result[domain.len+i] = seed[i] # Entropy history/output is an exact fixed word.
  if ticketed: result[result.high] = attempt # Ticket entry index is E1, never a compact natural.

## Authenticate a structurally decoded full header using posterior C(4)/C(8) and retained parent C(6)/time.
## Derive posterior eta[3] from parent eta[2] on any epoch crossing, otherwise parent eta[3].
## This history rotation does not depend on new eta[0], avoiding circular trust in unverified entropy.
## Marker validity, earlier stage lineage and parent/extrinsic commitments remain caller responsibilities.
proc authenticateSafroleSeal*(candidate: OwnedHeader, schedule, active: openArray[byte],
    previous: StateTime, parentEntropy: StateEntropy,
        config: SafroleAuthConfig): SafroleAuthResult =
  let epoch = uint64(config.state.epochSlots)
  if epoch == 0:
    return SafroleAuthResult(status: SafroleAuthError.InvalidConfig) # No modulo or epoch division under a zero length.
  let info = headerInfo(candidate)
  if info.error != HeaderError.None:
    return SafroleAuthResult(status: SafroleAuthError.InvalidHeader) # A default owner is not a complete signed header.
  let target = uint32(info.value.unsigned.slot)
  if target <= uint32(previous):
    return SafroleAuthResult(status: SafroleAuthError.InvalidSlot) # Repeated, backward and wrapped slots reject before native work.
  if uint64(info.value.consumed) > uint64(config.maxHeaderBytes):
    return SafroleAuthResult(status: SafroleAuthError.LimitExceeded) # Bound the complete header before allocating its signing copy.
  let oversizedSchedule = uint64(schedule.len) > uint64(config.state.maxBytes)
  let oversizedActive = uint64(active.len) > uint64(config.state.validators.maxBytes)
  if oversizedSchedule or oversizedActive:
    return SafroleAuthResult(status: SafroleAuthError.LimitExceeded) # Bound both dynamic borrowed stage inputs before copying either.
  let parsed = decodeSafroleState(schedule, config.state)
  if parsed.error != StateComponentError.None:
    return SafroleAuthResult(status: codecError(parsed.error)) # No malformed/default slot-sealer source.
  let roster = decodeStateValidators(active, config.state.validators)
  if roster.error != StateComponentError.None:
    return SafroleAuthResult(status: codecError(roster.error)) # Structural active population is independent of pending count.
  if parsed.value.consumed != schedule.len or roster.value.consumed != active.len:
    return SafroleAuthResult(status: SafroleAuthError.InvalidState) # Exact chapters reject otherwise valid prefixes with suffixes.
  let author = uint64(uint16(info.value.unsigned.author))
  let population = validatorCount(roster.value.value).value
  if author >= uint64(population):
    return SafroleAuthResult(status: SafroleAuthError.InvalidAuthor) # Decoder's profile maximum is not the actual posterior population.
  let record = validatorAt(roster.value.value, StateValidatorIndex(author)).value
  let public = array[32, byte](record.bandersnatch)
  let phase = uint64(target) mod epoch
  let sealer = safroleInfo(parsed.value.snapshot).value
  let ticketed = sealer.kind == SealerKind.Tickets
  var attempt = 0'u8
  var ticketId = default(array[32, byte])
  if ticketed:
    let ticket = sealerTicketAt(parsed.value.snapshot, SafroleStateIndex(phase)).value
    attempt = byte(ticket.attempt)
    ticketId = array[32, byte](ticket.id) # Bind only after verification, never trust signature output bytes directly.
  else:
    let selected = sealerKeyAt(parsed.value.snapshot, SafroleStateIndex(phase)).value
    if array[32, byte](selected) != public:
      return SafroleAuthResult(status: SafroleAuthError.InvalidAuthor) # Fallback author must match this exact cyclic schedule key.
  let crossed = uint64(target) div epoch > uint64(uint32(previous)) div epoch
  let history = array[32, byte](parentEntropy[if crossed: 2 else: 3])
  let sealContext = context((if ticketed: "jam_ticket_seal" else: "jam_fallback_seal"), history,
      ticketed, attempt)
  let unsigned = unsignedPart(candidate)
  if unsigned.error != HeaderError.None:
    return SafroleAuthResult(status: SafroleAuthError.InvalidHeader) # Only a signing owner selected from this exact full header is usable.
  var signing = newSeq[byte](info.value.unsigned.consumed)
  let copied = encodeOwnedUnsignedHeader(unsigned.value, signing)
  if copied.error != HeaderError.None or copied.value != signing.len:
    return SafroleAuthResult(status: SafroleAuthError.InvalidHeader) # Additional data must be the entire exact unsigned serialization.
  let seal = verify(BsPublicKey(public), BsSignature(array[96, byte](info.value.seal)), sealContext, signing)
  if seal.error != BsError.None:
    return SafroleAuthResult(status: proofError(seal.error,
        SafroleAuthError.InvalidSeal)) # No unverified seal output can seed entropy verification.
  if ticketed and array[32, byte](seal.value) != ticketId:
    return SafroleAuthResult(status: SafroleAuthError.InvalidTicket) # A valid signature alone does not prove ownership of this winning ticket.
  let entropyContext = context("jam_entropy", array[32, byte](seal.value), false, 0)
  let entropy = verify(BsPublicKey(public), BsSignature(array[96, byte](
      info.value.unsigned.entropyProof)), entropyContext, [])
  if entropy.error != BsError.None:
    return SafroleAuthResult(status: proofError(entropy.error,
        SafroleAuthError.InvalidEntropy)) # Entropy uses empty additional data and the same indexed author.
  SafroleAuthResult(status: SafroleAuthError.None, completed: SafroleAuthentication(
    header: candidate, entropy: EntropyInput(array[32, byte](entropy.value)),
        sealOutput: seal.value, ticketed: ticketed))
