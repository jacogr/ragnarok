## GP v0.7.1 assurancesig: fixed owned transcripts and stateless validator-key/parent verification.
import ./primitives
import ../src/assurances

type
  # Expected block parent is distinct from an assurance anchor and from a computed digest.
  AssuranceParent* = distinct array[32, byte]
  # The normative domain and 32-byte digest form one owned, signature-independent message.
  AssuranceSigningMessage* = distinct array[46, byte]
  # Only completed verification may produce a certified count; this is not availability/state approval.
  VerifiedAssuranceCount* = distinct uint64
  # Context errors preserve precise configuration, structural, parent and cryptographic failures.
  AssuranceContextError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidKeySet, LimitExceeded, InvalidValidator,
    NonCanonical, WrongParent, InvalidSignature, BackendFailure
  # Default and failure alternatives have no transcript, count or partially validated value.
  AssuranceContextResult*[T] = object
    case error*: AssuranceContextError
    of AssuranceContextError.None:
      # Success alone exposes the fully completed message or verification count.
      value*: T
    else:
      # A failed result carries only its reason.
      discard

# Validate all native bit storage before constructing the protocol's fixed-width transcript.
proc canonicalBits(bits: AssuranceBits, cores: CoreCount): bool {.raises: [].} =
  let width = (int(cores)+7) div 8
  let remainder = int(cores) mod 8
  # High bits in a partial final octet refer to nonexistent cores.
  if remainder != 0 and (int(bits.bytes[width-1]) shr remainder) != 0: return false
  # Nonzero unused native storage must not disappear silently from the signed message.
  for i in width..<43:
    if bits.bytes[i] != 0:
      # This profile has no canonical representation of that storage octet.
      return false
  true

# Build exactly $jam_available || Blake2b-256(parent || fixed bits), without retaining any input.
proc assuranceMessage*(parent: AssuranceParent, bits: AssuranceBits,
                       cores: CoreCount): AssuranceContextResult[
                           AssuranceSigningMessage] {.raises: [].} =
  # Validate the unsigned profile before narrowing or indexing the final bitfield byte.
  if uint64(cores) < 1 or uint64(cores) > 341:
    return AssuranceContextResult[AssuranceSigningMessage](
        error: AssuranceContextError.InvalidConfig)
  # Signing a noncanonical native value would hide caller data and produce a misleading credential.
  if not canonicalBits(bits, cores):
    return AssuranceContextResult[AssuranceSigningMessage](
        error: AssuranceContextError.NonCanonical)
  let width = (int(cores)+7) div 8
  var transcript: array[75, byte]
  let parentBytes = array[32, byte](parent)
  # Parent identity bytes precede the fixed bitfield with no discriminator or length prefix.
  for i in 0..<32: transcript[i] = parentBytes[i]
  # Hash only serialized profile bytes, not the unused 43-byte storage suffix.
  for i in 0..<width: transcript[32+i] = bits.bytes[i]
  let hashed = blake2b256(transcript.toOpenArray(0, 31+width))
  # No failed provider output can become a default all-zero signing message.
  if hashed.error != CryptoError.None:
    return AssuranceContextResult[AssuranceSigningMessage](
        error: AssuranceContextError.BackendFailure)
  var message: array[46, byte]
  const domain = "$jam_available"
  # The leading dollar sign is signed; no terminator or extra domain hash is inserted.
  for i in 0..<domain.len: message[i] = byte(domain[i])
  let digest = array[32, byte](hashed.value)
  # Blake2b is parameterized for 32 output bytes, preserving the digest's identity order.
  for i in 0..<32: message[14+i] = digest[i]
  AssuranceContextResult[AssuranceSigningMessage](error: AssuranceContextError.None,
    value: AssuranceSigningMessage(message))

# Verify stable borrowed records and key mapping without allocations, mutation or retained pointers.
proc verifyAssurances*(values: openArray[Assurance], config: AssuranceConfig,
                       parent: AssuranceParent, keys: openArray[EdPublicKey]):
                       AssuranceContextResult[VerifiedAssuranceCount] {.raises: [].} =
  # Configuration has precedence over empty input and absent validator keys.
  if uint64(config.cores) < 1 or uint64(config.cores) > 341 or
      uint64(config.validators) < 1 or uint64(config.validators) > 1023:
    return AssuranceContextResult[VerifiedAssuranceCount](
        error: AssuranceContextError.InvalidConfig)
  # The key table is indexed by validator identity, never by a record's position in this batch.
  if uint64(keys.len) != uint64(config.validators):
    return AssuranceContextResult[VerifiedAssuranceCount](
        error: AssuranceContextError.InvalidKeySet)
  # A bounded count also bounds all subsequent native loops.
  if uint64(values.len) > uint64(config.validators):
    return AssuranceContextResult[VerifiedAssuranceCount](
        error: AssuranceContextError.LimitExceeded)
  var previous = -1
  let expected = array[32, byte](parent)
  # Complete every structural/context check before an early invalid signature can hide a later failure.
  for value in values:
    if uint64(value.validator) >= uint64(config.validators):
      # E2 width does not prove membership in this configured validator set.
      return AssuranceContextResult[VerifiedAssuranceCount](
          error: AssuranceContextError.InvalidValidator)
    # Unique ascending indices prevent duplicate validator credentials within the same extrinsic.
    if int(value.validator) <= previous:
      return AssuranceContextResult[VerifiedAssuranceCount](
          error: AssuranceContextError.NonCanonical)
    # Validate unused bits and storage even for values constructed directly by a native caller.
    if not canonicalBits(value.bits, config.cores):
      return AssuranceContextResult[VerifiedAssuranceCount](
          error: AssuranceContextError.NonCanonical)
    # Every anchor must bind to the externally supplied expected block parent.
    if value.anchor.bytes != expected:
      return AssuranceContextResult[VerifiedAssuranceCount](
          error: AssuranceContextError.WrongParent)
    previous = int(value.validator)
  # Only a fully valid context proceeds to ordinary backend Ed25519 verification.
  for value in values:
    let message = assuranceMessage(parent, value.bits, config.cores)
    let signature = importSignature(value.signature.bytes)
    # Backend failure never turns into an ordinary negative/positive credential by fallback.
    if message.error != AssuranceContextError.None or signature.error != CryptoError.None:
      return AssuranceContextResult[VerifiedAssuranceCount](
          error: AssuranceContextError.BackendFailure)
    let bytes = array[46, byte](message.value)
    # The provider's existing exceptional-point policy is unchanged and remains documented separately.
    if not verify(keys[int(value.validator)], signature.value, bytes):
      return AssuranceContextResult[VerifiedAssuranceCount](
          error: AssuranceContextError.InvalidSignature)
  AssuranceContextResult[VerifiedAssuranceCount](error: AssuranceContextError.None,
    value: VerifiedAssuranceCount(values.len))
