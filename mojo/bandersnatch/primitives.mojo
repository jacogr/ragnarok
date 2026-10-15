from std.collections import Array, Span, Optional
from std.ffi import external_call, c_size_t
from std.sys import size_of
from codec.types import Failure, CheckedResult, fail
from crypto.primitives import PublicBytes


comptime BsPublicKey = PublicBytes[10, 32]
comptime BsSignature = PublicBytes[11, 96]
comptime BsRingProof = PublicBytes[12, 784]
comptime BsRingRoot = PublicBytes[13, 144]
comptime BsOutput = PublicBytes[14, 32]
comptime NativePointer = OpaquePointer[mut=True, MutUntrackedOrigin]


# Native language state binds borrowed aliases to one Rust handle and its explicit closed status.
@fieldwise_init
struct NativeState(Movable):
    var handle: Optional[NativePointer]
    var kind: Int


# Scalar owner aliases retain only an opaque native-language state pointer, never Rust private bytes.
@fieldwise_init
struct BsKey(Copyable, Movable):
    var _state: Optional[NativePointer]


# Setup has a distinct static domain and owns the selected immutable historical SRS/domain parameters.
@fieldwise_init
struct BsSetup(Copyable, Movable):
    var _state: Optional[NativePointer]


# Map exactly the maintained Rust status ABI into failure-only native results.
def failure(status: UInt32) -> Failure:
    # Length, encoding, missing owner, verification, backend and caught-panic remain distinct.
    if status == 1:
        return fail["bs:2"]()
    elif status == 2:
        return fail["bs:3"]()
    elif status == 3:
        return fail["bs:4"]()
    elif status == 4:
        return fail["bs:5"]()
    elif status == 6:
        return fail["bs:7"]()
    else:
        # Unknown ABI statuses fail closed as backend errors.
        return fail["bs:6"]()


# Retain a Rust handle in shared native state so close invalidates all aliases consistently.
def adopt(var handle: Optional[NativePointer], kind: Int) -> CheckedResult[NativePointer]:
    var opaque = external_call["malloc", Optional[NativePointer]](c_size_t(size_of[NativeState]()))
    # A failed native-language allocation must still retire the just-created Rust owner.
    if not opaque:
        if kind == 0:
            # Secret destruction zeroizes the original Rust-owned scalar.
            external_call["bs_key_free", NoneType](handle)
        else:
            # Setup destruction releases the immutable parameter allocation.
            external_call["bs_setup_free", NoneType](handle)
        return CheckedResult[NativePointer](failure(5))
    opaque.value().unsafe_bitcast[NativeState]().unsafe_write(NativeState(handle^, kind))
    return CheckedResult[NativePointer](opaque.value())


# Import one exact canonical nonzero 32-byte scalar; Rust validates it without Mojo truncation.
def import_scalar(data: Span[mut=False, UInt8, _]) -> CheckedResult[BsKey]:
    var handle = Optional[NativePointer]()
    var status = external_call["bs_key_new", UInt32](
        data.unsafe_ptr().as_unsafe_any_origin(), c_size_t(len(data)), Pointer(to=handle)
    )
    # Failed scalar import exposes neither an opaque Rust allocation nor a default identity.
    if status != 0:
        return CheckedResult[BsKey](failure(status))
    var state = adopt(handle^, 0)
    # Preserve allocation failure after the Rust allocation has been retired.
    if state.isa[Failure]():
        return CheckedResult[BsKey](state[Failure].copy())
    return CheckedResult[BsKey](BsKey(state[NativePointer]))


# Select exactly one historical domain capacity, bounded by the existing ABI's 1..1023 contract.
def new_setup(capacity: Int) -> CheckedResult[BsSetup]:
    # Signed capacities must not wrap into size_t before validation.
    if capacity < 1 or capacity > 1023:
        return CheckedResult[BsSetup](failure(1))
    var handle = Optional[NativePointer]()
    var status = external_call["bs_setup_new", UInt32](c_size_t(capacity), Pointer(to=handle))
    # Failed domain setup has no usable parameter owner.
    if status != 0:
        return CheckedResult[BsSetup](failure(status))
    var state = adopt(handle^, 1)
    if state.isa[Failure]():
        # The temporary Rust owner was already released on adoption failure.
        return CheckedResult[BsSetup](state[Failure].copy())
    return CheckedResult[BsSetup](BsSetup(state[NativePointer]))


# Explicit unsafe state access is confined to native owner operations; it exposes no Rust private layout.
def unsafe_state(opaque: NativePointer) -> Pointer[NativeState, MutUntrackedOrigin]:
    return opaque.unsafe_bitcast[NativeState]()


# Translate a default/closed scalar alias into the null handle expected by the primitive ABI.
def key_handle(key: BsKey) -> Optional[NativePointer]:
    # Default native owners have no state allocation.
    if not key._state:
        return None
    return unsafe_state(key._state.value())[].handle


# Translate a default/closed setup alias into a null primitive parameter handle.
def setup_handle(setup: BsSetup) -> Optional[NativePointer]:
    # Missing state must not fabricate an SRS/domain owner.
    if not setup._state:
        return None
    return unsafe_state(setup._state.value())[].handle


# Close the shared Rust allocation, leaving alias-visible closed state until the original state owner retires.
def close_state(opaque: Optional[NativePointer]):
    # Default owner closure is harmless.
    if not opaque:
        return
    ref state = unsafe_state(opaque.value())[]
    # A second close must not free the Rust handle twice.
    if not state.handle:
        return
    if state.kind == 0:
        # Scalar destruction zeroizes retained secret state in Rust.
        external_call["bs_key_free", NoneType](state.handle)
    else:
        # Setup destruction releases only its immutable domain parameters.
        external_call["bs_setup_free", NoneType](state.handle)
    state.handle = None


# Erase a scalar while invalidating all existing aliases before their native state is released.
def close_key(key: BsKey):
    close_state(key._state)


# Retire domain parameters while making all setup aliases report missing owner.
def close_setup(setup: BsSetup):
    close_state(setup._state)


# Free one original language-state allocation after all scalar aliases stop using it.
def release_key(mut key: BsKey):
    # Default owners have no state allocation.
    if not key._state:
        return
    close_key(key)
    unsafe_state(key._state.value()).unsafe_deinit_pointee()
    external_call["free", NoneType](key._state.value())
    key._state = None


# Free one original setup state after all borrowed aliases stop using it.
def release_setup(mut setup: BsSetup):
    # Releasing an empty/default setup is harmless.
    if not setup._state:
        return
    close_setup(setup)
    unsafe_state(setup._state.value()).unsafe_deinit_pointee()
    external_call["free", NoneType](setup._state.value())
    setup._state = None


# Derive an owned canonical 32-byte public key from a live retained Rust scalar.
def public_key(key: BsKey) -> CheckedResult[BsPublicKey]:
    var output = Array[UInt8, 32](fill=0)
    var status = external_call["bs_public", UInt32](
        key_handle(key), output.unsafe_ptr().as_unsafe_any_origin()
    )
    # No native failure may expose the temporary default key bytes.
    if status != 0:
        return CheckedResult[BsPublicKey](failure(status))
    return CheckedResult[BsPublicKey](BsPublicKey(output^))


# Own one exact public encoding only after canonical prime-subgroup validation by the historical backend.
def import_public(data: Span[mut=False, UInt8, _]) -> CheckedResult[BsPublicKey]:
    var status = external_call["bs_validate_public", UInt32](
        data.unsafe_ptr().as_unsafe_any_origin(), c_size_t(len(data))
    )
    # Invalid widths/points have no usable nominal key alternative.
    if status != 0:
        return CheckedResult[BsPublicKey](failure(status))
    var bytes = Array[UInt8, 32](fill=0)
    # Preserve the exact checked encoding without retaining mutable caller storage.
    for i in range(32):
        bytes[i] = data[i]
    return CheckedResult[BsPublicKey](BsPublicKey(bytes^))


# Own a fixed proof/root encoding; cryptographic validity remains a verification gate.
def import_bytes[
    kind: Int, length: Int
](data: Span[mut=False, UInt8, _]) -> CheckedResult[PublicBytes[kind, length]]:
    # Reject wrong widths before any copy or partial nominal value construction.
    if len(data) != length:
        return CheckedResult[PublicBytes[kind, length]](failure(1))
    var bytes = Array[UInt8, length](fill=0)
    # Every completed output byte belongs to the exact original encoding.
    for i in range(length):
        bytes[i] = data[i]
    return CheckedResult[PublicBytes[kind, length]](PublicBytes[kind, length](bytes^))


# Sign raw context and additional bytes separately using the original IETF suite's 96-byte encoding.
def sign(
    key: BsKey, context: Span[mut=False, UInt8, _], additional: Span[mut=False, UInt8, _]
) -> CheckedResult[BsSignature]:
    var output = Array[UInt8, 96](fill=0)
    var status = external_call["bs_sign", UInt32](
        key_handle(key),
        context.unsafe_ptr().as_unsafe_any_origin(),
        c_size_t(len(context)),
        additional.unsafe_ptr().as_unsafe_any_origin(),
        c_size_t(len(additional)),
        output.unsafe_ptr().as_unsafe_any_origin(),
    )
    # Failure carries no signature or verified output metadata.
    if status != 0:
        return CheckedResult[BsSignature](failure(status))
    return CheckedResult[BsSignature](BsSignature(output^))


# Extract the output hash only after a complete typed contextual signature verifies successfully.
def verify(
    key: BsPublicKey,
    signature: BsSignature,
    context: Span[mut=False, UInt8, _],
    additional: Span[mut=False, UInt8, _],
) -> CheckedResult[BsOutput]:
    var output = Array[UInt8, 32](fill=0)
    var status = external_call["bs_verify", UInt32](
        key.bytes.unsafe_ptr().as_unsafe_any_origin(),
        signature.bytes.unsafe_ptr().as_unsafe_any_origin(),
        c_size_t(96),
        context.unsafe_ptr().as_unsafe_any_origin(),
        c_size_t(len(context)),
        additional.unsafe_ptr().as_unsafe_any_origin(),
        c_size_t(len(additional)),
        output.unsafe_ptr().as_unsafe_any_origin(),
    )
    # Invalid proofs expose no unverified output hash.
    if status != 0:
        return CheckedResult[BsOutput](failure(status))
    return CheckedResult[BsOutput](BsOutput(output^))


# GP ring padding policy stays in Mojo: substitute invalid encodings with the pinned suite's padding point.
def normalize_ring(data: Span[mut=False, UInt8, _]) -> CheckedResult[List[UInt8]]:
    # Ring storage is bounded and each member has exact compressed-point width.
    if len(data) == 0 or len(data) % 32 != 0 or len(data) // 32 > 1023:
        return CheckedResult[List[UInt8]](failure(1))
    var padding = Array[UInt8, 32](fill=0)
    var status = external_call["bs_padding", UInt32](padding.unsafe_ptr().as_unsafe_any_origin())
    # A backend failure cannot substitute a default padding point.
    if status != 0:
        return CheckedResult[List[UInt8]](failure(status))
    var output = List[UInt8](length=len(data), fill=0)
    # Validate each point separately; valid identity remains unchanged and is rejected by the primitive guard.
    for index in range(len(data) // 32):
        var start = index * 32
        var verdict = external_call["bs_validate_public", UInt32](
            data.unsafe_ptr().unsafe_offset(start).as_unsafe_any_origin(), c_size_t(32)
        )
        # Only invalid encoding is the specified substitution case; other native failures propagate.
        if verdict != 0 and verdict != 2:
            return CheckedResult[List[UInt8]](failure(verdict))
        # Preserve valid original bytes or substitute every byte of the exact padding encoding.
        for i in range(32):
            if verdict == 0:
                output[start + i] = data[start + i]
            else:
                # Invalid-member padding is language policy, never a hidden Rust codec transform.
                output[start + i] = padding[i]
    return CheckedResult[List[UInt8]](output^)


# Normalize the ring natively, then commit ordered members using the explicit historical SRS/domain owner.
def commit_ring(setup: BsSetup, members: Span[mut=False, UInt8, _]) -> CheckedResult[BsRingRoot]:
    var normalized = normalize_ring(members)
    # Bad syntax/policy never reaches the primitive as a default ring.
    if normalized.isa[Failure]():
        return CheckedResult[BsRingRoot](normalized[Failure].copy())
    var ring = normalized[List[UInt8]].copy()
    var output = Array[UInt8, 144](fill=0)
    var status = external_call["bs_commit", UInt32](
        setup_handle(setup),
        ring.unsafe_ptr().as_imm().as_unsafe_any_origin(),
        c_size_t(len(ring)),
        output.unsafe_ptr().as_unsafe_any_origin(),
    )
    # Failed commitment exposes no root to an application caller.
    if status != 0:
        return CheckedResult[BsRingRoot](failure(status))
    return CheckedResult[BsRingRoot](BsRingRoot(output^))


# Prove only a matching live key/index within the selected explicit domain and normalized ring.
def sign_ring(
    setup: BsSetup,
    key: BsKey,
    index: Int,
    members: Span[mut=False, UInt8, _],
    context: Span[mut=False, UInt8, _],
    additional: Span[mut=False, UInt8, _],
) -> CheckedResult[BsRingProof]:
    var normalized = normalize_ring(members)
    # Preserve normalization failure precedence before index validation, matching the other adapters.
    if normalized.isa[Failure]():
        return CheckedResult[BsRingProof](normalized[Failure].copy())
    # A negative native-language index cannot wrap into size_t.
    if index < 0:
        return CheckedResult[BsRingProof](failure(1))
    var ring = normalized[List[UInt8]].copy()
    var output = Array[UInt8, 784](fill=0)
    var status = external_call["bs_ring_sign", UInt32](
        setup_handle(setup),
        key_handle(key),
        c_size_t(index),
        ring.unsafe_ptr().as_imm().as_unsafe_any_origin(),
        c_size_t(len(ring)),
        context.unsafe_ptr().as_unsafe_any_origin(),
        c_size_t(len(context)),
        additional.unsafe_ptr().as_unsafe_any_origin(),
        c_size_t(len(additional)),
        output.unsafe_ptr().as_unsafe_any_origin(),
    )
    # Invalid membership/backend proof failures have no partial anonymous proof alternative.
    if status != 0:
        return CheckedResult[BsRingProof](failure(status))
    return CheckedResult[BsRingProof](BsRingProof(output^))


# Verify the complete root-bound anonymous proof before exposing its owned 32-byte output.
def verify_ring(
    setup: BsSetup,
    root: BsRingRoot,
    proof: BsRingProof,
    context: Span[mut=False, UInt8, _],
    additional: Span[mut=False, UInt8, _],
) -> CheckedResult[BsOutput]:
    var output = Array[UInt8, 32](fill=0)
    var status = external_call["bs_ring_verify", UInt32](
        setup_handle(setup),
        root.bytes.unsafe_ptr().as_unsafe_any_origin(),
        proof.bytes.unsafe_ptr().as_unsafe_any_origin(),
        c_size_t(784),
        context.unsafe_ptr().as_unsafe_any_origin(),
        c_size_t(len(context)),
        additional.unsafe_ptr().as_unsafe_any_origin(),
        c_size_t(len(additional)),
        output.unsafe_ptr().as_unsafe_any_origin(),
    )
    # Verification failure exposes no unverified output bytes.
    if status != 0:
        return CheckedResult[BsOutput](failure(status))
    return CheckedResult[BsOutput](BsOutput(output^))
