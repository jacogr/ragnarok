from std.collections import Span, Optional
from std.ffi import external_call, c_int
from crypto.primitives import *


# One controller-owned record stays at a stable address until its exact native worker has joined.
@fieldwise_init
struct WorkerContext(Copyable, Movable):
    var identity: UInt8
    var failed: Bool


# Each foreign worker owns an independent deterministic seed and all scratch/output values until return.
def worker(
    argument: OpaquePointer[mut=True, _]
) abi("C") -> Optional[OpaquePointer[mut=True, MutUntrackedOrigin]]:
    var context = argument.unsafe_bitcast[WorkerContext]()
    var bytes = List[UInt8](length=32, fill=0)
    bytes[0] = context[].identity
    var loaded = import_seed(Span(bytes))
    # Allocation/import failure is reported through the joined worker verdict.
    if not loaded.isa[EdSeed]():
        return None
    var seed = loaded[EdSeed].copy()
    var failed = False
    try:
        var key = public_key(seed)
        var initial_b = blake2b256(Span(bytes))
        var initial_k = keccak256(Span(bytes))
        # Every worker initializes its own live key and baseline hash values.
        if (
            not key.isa[EdPublicKey]()
            or not initial_b.isa[Blake2bHash]()
            or not initial_k.isa[KeccakHash]()
        ):
            return None
        var public = key[EdPublicKey].copy()
        var expected_b = initial_b[Blake2bHash].copy()
        var expected_k = initial_k[KeccakHash].copy()
        # Repeated signing and hashing exercise same-process primitive state concurrently.
        for _ in range(128):
            var signature = sign(seed, Span(bytes))
            var b = blake2b256(Span(bytes))
            var k = keccak256(Span(bytes))
            # Failed operations must not expose scratch default encodings.
            if (
                not signature.isa[EdSignature]()
                or not b.isa[Blake2bHash]()
                or not k.isa[KeccakHash]()
            ):
                failed = True
                break
            # Verify the exact owned signature against this worker's identity and raw message.
            if not verify(public, signature[EdSignature], Span(bytes)):
                failed = True
                break
            var actual_b = b[Blake2bHash].copy()
            var actual_k = k[KeccakHash].copy()
            # All output bytes must remain stable across concurrent backend calls.
            for i in range(32):
                if (
                    actual_b.bytes[i] != expected_b.bytes[i]
                    or actual_k.bytes[i] != expected_k.bytes[i]
                ):
                    failed = True
    finally:
        # Secret storage is erased and freed on every worker return path.
        release_seed(seed)
    context[].failed = failed
    return None


# Start four bounded pthread workers through public POSIX FFI and join every created worker.
def concurrent() raises:
    var threads = List[UInt64](length=4, fill=0)
    var contexts = List[WorkerContext]()
    # Allocate all callback records before launching; no append may invalidate a retained address.
    for i in range(4):
        contexts.append(WorkerContext(UInt8(i + 1), True))
    var started = 0
    var failed = False
    try:
        # Both supported 64-bit POSIX ABIs represent pthread_t in one pointer-sized slot.
        for i in range(4):
            var status = external_call["pthread_create", c_int](
                threads.unsafe_ptr().unsafe_offset(i),
                Optional[OpaquePointer[mut=True, MutUntrackedOrigin]](None),
                worker,
                contexts.unsafe_ptr()
                .unsafe_offset(i)
                .unsafe_bitcast[NoneType]()
                .as_unsafe_any_origin(),
            )
            # A partial launch still joins all earlier workers before their owners can retire.
            if status != 0:
                failed = True
                break
            started += 1
    finally:
        # Every worker finishes and retires its independent native state before returning to the controller.
        for i in range(started):
            var verdict = Optional[OpaquePointer[mut=True, MutUntrackedOrigin]](None)
            var status = external_call["pthread_join", c_int](threads[i], Pointer(to=verdict))
            # Join errors and nonzero worker verdicts are conformance failures.
            if status != 0 or contexts[i].failed:
                failed = True
    # No failed launch or worker may be reported as a successful same-process concurrency test.
    if failed:
        raise Error("native crypto worker failed")
    print("ok")
