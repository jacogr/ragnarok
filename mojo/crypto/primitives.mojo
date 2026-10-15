from std.collections import Array, Span, Optional
from std.ffi import external_call, c_int, c_size_t
from std.sys import size_of
from codec.types import Failure, CheckedResult, fail


# Nominal owned public byte encodings; algorithm/key/signature specializations are distinct static types.
@fieldwise_init
struct PublicBytes[kind: Int, length: Int](Copyable, Movable):
    var bytes: Array[UInt8, Self.length]


comptime Blake2bHash = PublicBytes[0, 32]
comptime KeccakHash = PublicBytes[1, 32]
comptime EdPublicKey = PublicBytes[2, 32]
comptime EdSignature = PublicBytes[3, 64]


# Opaque retained seed storage; no caller input pointer survives import.
@fieldwise_init
struct SeedStorage(Movable):
    var bytes: Array[UInt8, 32]
    var alive: Bool


# One explicit release owner, as for Odin; copied handles are aliases and clear invalidates all aliases.
@fieldwise_init
struct EdSeed(Copyable, Movable):
    var _opaque: Optional[OpaquePointer[mut=True, MutUntrackedOrigin]]


# Internal access is explicitly unsafe and never part of the ordinary public seed operations.
def unsafe_seed_storage(seed: EdSeed) -> Pointer[SeedStorage, MutUntrackedOrigin]:
    return seed._opaque.value().unsafe_bitcast[SeedStorage]()


# Import exactly one RFC 8032 seed into independent native storage, including a valid all-zero seed.
def import_seed(data: Span[mut=False, UInt8, _]) -> CheckedResult[EdSeed]:
    # Width is validated before creating a retained owner.
    if len(data) != 32:
        return CheckedResult[EdSeed](fail["invalidlength"]())
    var opaque = external_call["malloc", Optional[OpaquePointer[mut=True, MutUntrackedOrigin]]](
        c_size_t(size_of[SeedStorage]())
    )
    # Failed allocation exposes no default seed identity.
    if not opaque:
        return CheckedResult[EdSeed](fail["allocationfailure"]())
    var bytes = Array[UInt8, 32](fill=0)
    # Deep copying prevents later input mutation from altering signatures.
    for i in range(32):
        bytes[i] = data[i]
    opaque.value().unsafe_bitcast[SeedStorage]().unsafe_write(SeedStorage(bytes^, True))
    return CheckedResult[EdSeed](EdSeed(opaque))


# Explicit backend wipe prevents ordinary optimizer removal and invalidates every borrowed seed alias.
def clear_seed(seed: EdSeed):
    # Null/default owners have no secret storage to erase.
    if not seed._opaque:
        return
    ref value = unsafe_seed_storage(seed)[]
    external_call["rc_wipe", NoneType](
        value.bytes.unsafe_ptr().unsafe_bitcast[NoneType](), c_size_t(32)
    )
    value.alive = False


# Release exactly one original owner after all aliases stop using it; erase even if clear was omitted.
def release_seed(mut seed: EdSeed):
    # Releasing an empty owner is harmless.
    if not seed._opaque:
        return
    clear_seed(seed)
    unsafe_seed_storage(seed).unsafe_deinit_pointee()
    external_call["free", NoneType](seed._opaque.value())
    seed._opaque = None


# Import exact public encodings; point/signature acceptance policy is applied by the pinned verifier.
def import_public(data: Span[mut=False, UInt8, _]) -> CheckedResult[EdPublicKey]:
    # Wrong widths cannot expose padded or truncated keys.
    if len(data) != 32:
        return CheckedResult[EdPublicKey](fail["invalidlength"]())
    var bytes = Array[UInt8, 32](fill=0)
    # Preserve every original public-key byte without decoding/re-encoding its point.
    for i in range(32):
        bytes[i] = data[i]
    return CheckedResult[EdPublicKey](EdPublicKey(bytes^))


# Import only an exact ordinary Ed25519 signature, with no implicit prehash/context mode.
def import_signature(data: Span[mut=False, UInt8, _]) -> CheckedResult[EdSignature]:
    # Fixed width is an import gate, independent from the eventual verification verdict.
    if len(data) != 64:
        return CheckedResult[EdSignature](fail["invalidlength"]())
    var bytes = Array[UInt8, 64](fill=0)
    # The output owns all signature bytes rather than retaining caller storage.
    for i in range(64):
        bytes[i] = data[i]
    return CheckedResult[EdSignature](EdSignature(bytes^))


# Blake2b-256 borrows raw bytes synchronously through the existing pristine BoringSSL primitive ABI.
def blake2b256(data: Span[mut=False, UInt8, _]) -> CheckedResult[Blake2bHash]:
    var output = Array[UInt8, 32](fill=0)
    # Native failure must never expose a temporary zero/default digest.
    if (
        external_call["rc_blake2b256", c_int](
            data.unsafe_ptr().as_unsafe_any_origin(),
            c_size_t(len(data)),
            output.unsafe_ptr().as_unsafe_any_origin(),
        )
        != 1
    ):
        return CheckedResult[Blake2bHash](fail["backendfailure"]())
    return CheckedResult[Blake2bHash](Blake2bHash(output^))


# Legacy Keccak uses suffix 0x01 through the existing pristine XKCP ABI, without adding JAM domains.
def keccak256(data: Span[mut=False, UInt8, _]) -> CheckedResult[KeccakHash]:
    var output = Array[UInt8, 32](fill=0)
    # Setup/backend errors have no public hash alternative.
    if (
        external_call["rc_keccak256", c_int](
            data.unsafe_ptr().as_unsafe_any_origin(),
            c_size_t(len(data)),
            output.unsafe_ptr().as_unsafe_any_origin(),
        )
        != 1
    ):
        return CheckedResult[KeccakHash](fail["backendfailure"]())
    return CheckedResult[KeccakHash](KeccakHash(output^))


# Derive public bytes only from a live retained seed; native expanded secret scratch is wiped by the ABI.
def public_key(seed: EdSeed) -> CheckedResult[EdPublicKey]:
    # Missing owners must not silently behave as an imported zero seed.
    if not seed._opaque:
        return CheckedResult[EdPublicKey](fail["invalidseed"]())
    ref value = unsafe_seed_storage(seed)[]
    # Explicitly cleared aliases are all invalidated before any backend call.
    if not value.alive:
        return CheckedResult[EdPublicKey](fail["invalidseed"]())
    var output = Array[UInt8, 32](fill=0)
    # Failed derivation exposes neither partial public bytes nor a default identity.
    if (
        external_call["rc_ed_public", c_int](
            value.bytes.unsafe_ptr().as_imm().as_unsafe_any_origin(),
            output.unsafe_ptr().as_unsafe_any_origin(),
        )
        != 1
    ):
        return CheckedResult[EdPublicKey](fail["backendfailure"]())
    return CheckedResult[EdPublicKey](EdPublicKey(output^))


# Sign the exact raw message with ordinary deterministic RFC 8032 Ed25519, without implicit hashing.
def sign(seed: EdSeed, message: Span[mut=False, UInt8, _]) -> CheckedResult[EdSignature]:
    # Empty/cleared handles cannot manufacture a usable signature.
    if not seed._opaque:
        return CheckedResult[EdSignature](fail["invalidseed"]())
    ref value = unsafe_seed_storage(seed)[]
    # A cleared live allocation remains invalid across every copied handle alias.
    if not value.alive:
        return CheckedResult[EdSignature](fail["invalidseed"]())
    var output = Array[UInt8, 64](fill=0)
    # Borrow pointers only until the synchronous primitive returns; C retains no Mojo owner.
    if (
        external_call["rc_ed_sign", c_int](
            value.bytes.unsafe_ptr().as_imm().as_unsafe_any_origin(),
            message.unsafe_ptr().as_unsafe_any_origin(),
            c_size_t(len(message)),
            output.unsafe_ptr().as_unsafe_any_origin(),
        )
        != 1
    ):
        return CheckedResult[EdSignature](fail["backendfailure"]())
    return CheckedResult[EdSignature](EdSignature(output^))


# Verify exact owned encodings under the pinned BoringSSL acceptance policy; rejection is ordinary False.
def verify(key: EdPublicKey, signature: EdSignature, message: Span[mut=False, UInt8, _]) -> Bool:
    return (
        external_call["rc_ed_verify", c_int](
            key.bytes.unsafe_ptr().as_unsafe_any_origin(),
            signature.bytes.unsafe_ptr().as_unsafe_any_origin(),
            message.unsafe_ptr().as_unsafe_any_origin(),
            c_size_t(len(message)),
        )
        == 1
    )
