from std.collections import Array, Span
from codec.types import CheckedResult, Failure, fail
from codec.assurances import Assurance, AssuranceBits, AssuranceConfig, CoreCount, valid_config
from .primitives import blake2b256, Blake2bHash, EdPublicKey, EdSignature, import_signature, verify


# Expected parent is independent of both a record anchor and any cryptographic digest domain.
@fieldwise_init
struct AssuranceParent(Copyable, Movable):
    var bytes: Array[UInt8, 32]


# Fixed owned transcript cannot be substituted for a signature or an ordinary hash.
@fieldwise_init
struct AssuranceSigningMessage(Copyable, Movable):
    var bytes: Array[UInt8, 46]


# This count certifies only completed context/signature checks, not state transition or availability.
@fieldwise_init
struct VerifiedAssuranceCount(Copyable, Movable):
    var value: UInt64


# Inspect all native bitset storage after the caller proves the supported unsigned core range.
def canonical_bits(bits: AssuranceBits, cores: CoreCount) -> Bool:
    var width = (Int(cores.value) + 7) // 8
    var remainder = Int(cores.value) % 8
    # High final-octet bits must not assign availability to nonexistent cores.
    if remainder != 0 and (Int(bits.bytes[width - 1]) >> remainder) != 0:
        return False
    # Reject data that would otherwise disappear outside the profile's fixed wire width.
    for i in range(width, 43):
        if bits.bytes[i] != 0:
            # Unused native storage has no canonical encoding in the selected profile.
            return False
    return True


# Build exactly $jam_available || Blake2b-256(parent || fixed bits), without a retained input borrow.
def assurance_message(
    parent: AssuranceParent, bits: AssuranceBits, cores: CoreCount
) -> CheckedResult[AssuranceSigningMessage]:
    comptime Result = CheckedResult[AssuranceSigningMessage]
    # Reject invalid unsigned configuration before narrowing or indexing the final bitfield octet.
    if cores.value < 1 or cores.value > 341:
        return Result(fail["invalidconfig"]())
    # Signing noncanonical storage would bind to a silently reduced native value.
    if not canonical_bits(bits, cores):
        return Result(fail["noncanonical"]())
    var width = (Int(cores.value) + 7) // 8
    var transcript = Array[UInt8, 75](fill=0)
    # Identity parent bytes precede the bitfield without a length prefix or discriminator.
    for i in range(32):
        transcript[i] = parent.bytes[i]
    # Hash only serialized profile bytes, never the unused native bitset suffix.
    for i in range(width):
        transcript[32 + i] = bits.bytes[i]
    var hashed = blake2b256(Span(transcript)[: 32 + width])
    # Failed provider calls expose no all-zero or partial signing message.
    if hashed.isa[Failure]():
        return Result(fail["backendfailure"]())
    var output = Array[UInt8, 46](fill=0)
    # Fixed ASCII $jam_available bytes avoid constructing an allocating runtime string.
    var domain: Array[UInt8, 14] = [36, 106, 97, 109, 95, 97, 118, 97, 105, 108, 97, 98, 108, 101]
    # The leading dollar sign is signed and no terminator is appended.
    for i in range(14):
        output[i] = domain[i]
    var digest = hashed[Blake2bHash]
    # Blake2b's 32-byte output parameterization differs from truncating its 64-byte digest.
    for i in range(32):
        output[14 + i] = digest.bytes[i]
    return Result(AssuranceSigningMessage(output^))


# Check stable borrowed records against the exact caller-supplied key mapping and expected parent.
def verify_assurances(
    values: Span[mut=False, Assurance, _],
    config: AssuranceConfig,
    parent: AssuranceParent,
    keys: Span[mut=False, EdPublicKey, _],
) -> CheckedResult[VerifiedAssuranceCount]:
    comptime Result = CheckedResult[VerifiedAssuranceCount]
    # Configuration precedes empty inputs and absent key tables.
    if not valid_config(config):
        return Result(fail["invalidconfig"]())
    # Validator identity selects the public key, independently of this batch's record positions.
    if UInt64(len(keys)) != config.validators.value:
        return Result(fail["invalidkeyset"]())
    # Policy bounds cap every subsequent loop without allocating protocol storage.
    if UInt64(len(values)) > config.validators.value:
        return Result(fail["limitexceeded"]())
    var previous = -1
    # Complete the entire structural/context preflight before considering any signature verdict.
    for i in range(len(values)):
        if UInt64(values[i].validator.value) >= config.validators.value:
            # E2 width does not prove configured validator membership.
            return Result(fail["invalidvalidator"]())
        # Unique ascending indices enforce one credential per validator.
        if Int(values[i].validator.value) <= previous:
            return Result(fail["noncanonical"]())
        # Direct native construction cannot bypass profile bitfield canonicality.
        if not canonical_bits(values[i].bits, config.cores):
            return Result(fail["noncanonical"]())
        # Every record independently binds to the externally supplied expected parent.
        for j in range(32):
            if values[i].anchor.bytes[j] != parent.bytes[j]:
                # Wrong parents must fail even if an earlier record has an invalid signature.
                return Result(fail["wrongparent"]())
        previous = Int(values[i].validator.value)
    # Only a completely valid context proceeds to ordinary provider verification.
    for i in range(len(values)):
        var message = assurance_message(parent, values[i].bits, config.cores)
        var signature = import_signature(Span(values[i].signature.bytes))
        # Unexpected hash/import failures remain typed backend failures without fallback.
        if message.isa[Failure]() or signature.isa[Failure]():
            return Result(fail["backendfailure"]())
        var bytes = message[AssuranceSigningMessage]
        # Existing exceptional-point provider policy is unchanged and remains documented separately.
        if not verify(
            keys[Int(values[i].validator.value)], signature[EdSignature], Span(bytes.bytes)
        ):
            return Result(fail["invalidsignature"]())
    return Result(VerifiedAssuranceCount(UInt64(len(values))))
