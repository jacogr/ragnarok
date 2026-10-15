from std.collections import Span, Optional
from std.ffi import external_call, c_int
from bandersnatch.primitives import *


# Controller-owned callback metadata outlives its worker and carries no shared primitive owner.
@fieldwise_init
struct WorkerContext(Copyable, Movable):
    var identity: UInt8
    var failed: Bool


# Each fixed native worker owns one Rust scalar and fresh contextual proof state for every call.
def worker(
    argument: OpaquePointer[mut=True, _]
) abi("C") -> Optional[OpaquePointer[mut=True, MutUntrackedOrigin]]:
    var context = argument.unsafe_bitcast[WorkerContext]()
    var scalar = List[UInt8](length=32, fill=0)
    scalar[0] = context[].identity
    var empty = List[UInt8]()
    var loaded = import_scalar(Span(scalar))
    # A failed import cannot expose a secret owner to later proof operations.
    if not loaded.isa[BsKey]():
        return None
    var key = loaded[BsKey].copy()
    try:
        var derived = public_key(key)
        # Derivation must produce a complete owned key before verification can use it.
        if not derived.isa[BsPublicKey]():
            return None
        var public = derived[BsPublicKey].copy()
        # Same-process concurrent calls share only immutable backend code and pinned parameters.
        for _ in range(32):
            var proof = sign(key, Span(scalar), Span(empty))
            # Failed signing must not supply a default proof to verification.
            if not proof.isa[BsSignature]():
                return None
            var verified = verify(public, proof[BsSignature], Span(scalar), Span(empty))
            # Output extraction is valid only in the verified success alternative.
            if not verified.isa[BsOutput]():
                return None
    finally:
        # Every path retires and zeroizes the original scalar allocation before the worker ends.
        release_key(key)
    context[].failed = False
    return None


# Launch and join four bounded native callbacks, matching the existing Bandersnatch concurrency workload.
def concurrent() raises:
    var threads = List[UInt64](length=4, fill=0)
    var contexts = List[WorkerContext]()
    # Allocate all callback records before launching; no append may invalidate a retained address.
    for i in range(4):
        contexts.append(WorkerContext(UInt8(i + 1), True))
    var started = 0
    var failed = False
    try:
        # Supported 64-bit pthread ABIs use one pointer-width slot per thread identifier.
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
            # Even a partial launch must join already-created workers before retiring controller storage.
            if status != 0:
                failed = True
                break
            started += 1
    finally:
        # Wait for every created worker's Rust-owner teardown before checking its verdict.
        for i in range(started):
            var verdict = Optional[OpaquePointer[mut=True, MutUntrackedOrigin]](None)
            var status = external_call["pthread_join", c_int](threads[i], Pointer(to=verdict))
            # Neither join failure nor proof failure may be reported as a passing workload.
            if status != 0 or contexts[i].failed:
                failed = True
    # A failed worker is a conformance failure, not an ordinary proof-rejection case.
    if failed:
        raise Error("native Bandersnatch worker failed")
    print("ok")
