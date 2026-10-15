from std.collections import Array, Span, Optional
from std.ffi import external_call, c_size_t, c_int
from std.sys import argv, size_of, get_defined_bool
from codec.types import *
from codec.scalar import *
from codec.bounded import *
from codec.composite import *
from codec.digest import *
from codec.owned import *
from crypto.primitives import blake2b256, Blake2bHash
from tests.support import hex_text, capacity


comptime ALLOCATIONS = get_defined_bool["ALLOCATIONS", False]()


# Prepared typed values and stable nonoverlapping buffers are owned before any operation is timed.
@fieldwise_init
struct BenchCase(Movable):
    var kind: String
    var operation: String
    var wire: List[UInt8]
    var output: List[UInt8]
    var offset: Int
    var length: Int
    var number: UInt64
    var values: List[FixedUnsigned]
    var decoded_values: List[FixedUnsigned]
    var digest: Optional[WorkDigest]
    var owner: OwnedFrame


# Trusted preflight/benchmark invariants fail-stop; malformed production codec inputs remain ordinary tagged failures.
def require(good: Bool):
    if not good:
        # No invalid preflight or silently failed operation may generate a successful timing record.
        external_call["abort", NoneType]()


# The independently compiled common C observer receives the complete value address but never reads its bytes.
def observe[T: AnyType](ref value: T):
    external_call["rb_observe", NoneType](
        Pointer(to=value).unsafe_bitcast[NoneType]().as_imm().as_unsafe_any_origin(),
        c_size_t(size_of[T]()),
    )


# Small fingerprint is checked independently after full untimed reconstruction has already validated every byte.
def mark(data: Span[mut=False, UInt8, _], length: Int) -> UInt64:
    var result = UInt64(length)
    if length > 0:
        # Zero-width encodings have no valid byte addresses to sample.
        result ^= UInt64(data[0]) ^ UInt64(data[length - 1])
    return result


# Preserve a real runtime-input operation boundary; the baseline shares this same noinline/observation overhead.
@no_inline
def step(mut item: BenchCase) -> UInt64:
    if item.kind == "baseline":
        # This control performs no hidden codec work or allocation.
        observe(item.number)
        return item.number
    elif item.kind == "natural":
        if item.operation == "encode":
            # Nominal input preparation is untimed; output remains fixed allocation-free local storage.
            var encoded = encode_natural(JamNatural(item.number))
            observe(encoded)
            return mark(Span(encoded.bytes), encoded.length)
        else:
            # Observe the complete decoded value/progress structure, not merely the printed fingerprint.
            var decoded = decode_natural(Span(item.wire))
            observe(decoded)
            require(decoded.isa[Decoded[JamNatural]]())
            var value = decoded[Decoded[JamNatural]].copy()
            return value.value.value ^ UInt64(value.consumed)
    elif item.kind == "fixed":
        if item.operation == "encode":
            # Requested width comes from the exact checked corpus representation, including zero width.
            var encoded = encode_fixed(FixedUnsigned(item.number), ByteWidth(len(item.wire)))
            observe(encoded)
            require(encoded.isa[Encoded]())
            var value = encoded[Encoded].copy()
            return mark(Span(value.bytes), value.length)
        else:
            # Every fixed bit pattern is decoded through the production width-validation API.
            var decoded = decode_fixed(Span(item.wire), ByteWidth(len(item.wire)))
            observe(decoded)
            require(decoded.isa[Decoded[FixedUnsigned]]())
            var value = decoded[Decoded[FixedUnsigned]].copy()
            return value.value.value ^ UInt64(value.consumed)
    elif item.kind == "blake2b":
        # M2 timing includes the existing pinned BoringSSL provider and Mojo FFI, not just compiler code.
        var hashed = blake2b256(Span(item.wire))
        observe(hashed)
        require(hashed.isa[Blake2bHash]())
        var value = hashed[Blake2bHash].copy()
        return mark(Span(value.bytes), 32)
    elif item.operation == "owned-encode":
        # Prepared snapshot encoding excludes a hidden decode or allocation within the measured operation.
        var result = encode_owned(item.owner, Span(item.output))
        require(result.isa[Written]())
        external_call["rb_observe", NoneType](
            item.output.unsafe_ptr().unsafe_bitcast[NoneType]().as_imm().as_unsafe_any_origin(),
            c_size_t(result[Written].written),
        )
        return mark(Span(item.output), result[Written].written)
    elif item.operation == "owned-decode":
        var kind = 4
        if item.kind == "blob":
            # Byte-string capture and full-digest capture are distinct public ownership schemas.
            kind = 0
        var result = capture(
            Span(item.wire),
            kind,
            ByteLimit(1048576),
            PreimageLimits(ElementLimit(0), ByteLimit(0), ByteLimit(0)),
        )
        require(result.isa[OwnedFrame]())
        var frame = result[OwnedFrame].copy()
        var info = owned_info(frame)
        require(info.isa[OwnedInfo]())
        var result_mark = UInt64(info[OwnedInfo].consumed)
        if item.kind == "blob":
            # Select length-only owner metadata; no original source span is retained by the operation.
            var length = owned_blob_length(frame, 0)
            require(length.isa[Int]())
            result_mark ^= UInt64(length[Int])
        else:
            # Fixed fields and refinement gas are copied from the owner after full digest validation.
            var digest = owned_digest_info(frame)
            require(digest.isa[OwnedDigestInfo]())
            var value = digest[OwnedDigestInfo].copy()
            result_mark ^= (
                UInt64(value.service.value)
                ^ value.accumulate_gas.value
                ^ value.refine.gas_used.value
            )
        observe(result)
        # Explicit last-owner release belongs inside the timed operation, matching ARC/Odin lifecycle scope.
        release(frame)
        return result_mark
    elif item.operation == "encode":
        var result: WriteResult
        if item.kind == "blob":
            # Caller-owned input/output buffers stay stable and separate through preflight and commit.
            result = encode_bytes(
                Span(item.wire)[item.offset : item.offset + item.length],
                ByteLimit(1048576),
                Span(item.output),
            )
        elif item.kind == "sequence":
            # The same typed E4 element values are reused rather than decoded inside the encoder timing.
            result = encode_sequence(
                Span(item.values), ByteWidth(4), ElementLimit(16384), Span(item.output)
            )
        else:
            # Prepared complete digest values retain output spans bound to this exact wire pool.
            result = encode_digest_borrowed(
                item.digest.value().copy(), Span(item.wire), ByteLimit(1048576), Span(item.output)
            )
        require(result.isa[Written]())
        external_call["rb_observe", NoneType](
            item.output.unsafe_ptr().unsafe_bitcast[NoneType]().as_imm().as_unsafe_any_origin(),
            c_size_t(result[Written].written),
        )
        return mark(Span(item.output), result[Written].written)
    elif item.kind == "blob":
        # Borrowed blob decoding validates framing without scanning or copying the opaque payload.
        var decoded = decode_bytes_borrowed(Span(item.wire), ByteLimit(1048576))
        observe(decoded)
        require(decoded.isa[Decoded[BlobSpan]]())
        var value = decoded[Decoded[BlobSpan]].copy()
        return UInt64(value.consumed) ^ UInt64(value.value.length)
    elif item.kind == "sequence":
        # The destination is prepared once and reused across every native typed decode call.
        var decoded = decode_sequence(
            Span(item.wire), ByteWidth(4), ElementLimit(16384), Span(item.decoded_values)
        )
        observe(decoded)
        external_call["rb_observe", NoneType](
            item.decoded_values.unsafe_ptr()
            .unsafe_bitcast[NoneType]()
            .as_imm()
            .as_unsafe_any_origin(),
            c_size_t(len(item.decoded_values) * size_of[FixedUnsigned]()),
        )
        require(decoded.isa[SequenceInfo]())
        var value = decoded[SequenceInfo].copy()
        return UInt64(value.consumed) ^ UInt64(value.count)
    else:
        # Every fixed hash, work branch and refinement metric remains visible to the common observer.
        var decoded = decode_digest_borrowed(Span(item.wire), ByteLimit(1048576))
        observe(decoded)
        require(decoded.isa[Decoded[WorkDigest]]())
        var value = decoded[Decoded[WorkDigest]].copy()
        return (
            UInt64(value.consumed)
            ^ UInt64(value.value.service.value)
            ^ value.value.accumulate_gas.value
            ^ value.value.refine.gas_used.value
        )


# Load and preflight one exact mathematical/published corpus file before entering any timed loop.
def prepare(var kind: String, var operation: String, path: String) raises -> BenchCase:
    var wire: List[UInt8]
    with open(path, "r") as file:
        wire = file.read_bytes()
    require(len(wire) <= 1048832)
    var size = len(wire)
    var item = BenchCase(
        kind^,
        operation^,
        wire^,
        List[UInt8](length=max(1, size), fill=0),
        0,
        0,
        0,
        List[FixedUnsigned](),
        List[FixedUnsigned](),
        None,
        OwnedFrame(None),
    )
    if item.kind == "baseline":
        # The common no-work control has the same independently expected runtime fingerprint.
        item.number = 17
    elif item.kind == "natural":
        var decoded = decode_natural(Span(item.wire))
        require(decoded.isa[Decoded[JamNatural]]())
        var value = decoded[Decoded[JamNatural]].copy()
        require(value.consumed == size)
        item.number = value.value.value
        var encoded = encode_natural(value.value)
        for i in range(encoded.length):
            # Full byte equality is checked outside timing, not inferred from a small fingerprint alone.
            require(encoded.bytes[i] == item.wire[i])
    elif item.kind == "fixed":
        var decoded = decode_fixed(Span(item.wire), ByteWidth(size))
        require(decoded.isa[Decoded[FixedUnsigned]]())
        var value = decoded[Decoded[FixedUnsigned]].copy()
        item.number = value.value.value
        var encoded = encode_fixed(value.value, ByteWidth(size))
        require(encoded.isa[Encoded]())
        var bytes = encoded[Encoded].copy()
        for i in range(size):
            # Width-zero fixtures intentionally perform no byte accesses.
            require(bytes.bytes[i] == item.wire[i])
    elif item.kind == "blob":
        var decoded = decode_bytes_borrowed(Span(item.wire), ByteLimit(1048576))
        require(decoded.isa[Decoded[BlobSpan]]())
        var value = decoded[Decoded[BlobSpan]].copy()
        require(value.consumed == size)
        item.offset = value.value.offset
        item.length = value.value.length
    elif item.kind == "sequence":
        var values = List[FixedUnsigned](length=16384, fill=FixedUnsigned(0))
        var decoded = decode_sequence(
            Span(item.wire), ByteWidth(4), ElementLimit(16384), Span(values)
        )
        require(decoded.isa[SequenceInfo]())
        require(decoded[SequenceInfo].consumed == size)
        var count = decoded[SequenceInfo].count
        item.values = List[FixedUnsigned](length=count, fill=FixedUnsigned(0))
        for i in range(count):
            # Trim prepared typed input to exactly the initialized prefix without changing its numeric values.
            item.values[i] = values[i].copy()
        item.decoded_values = List[FixedUnsigned](length=max(1, count), fill=FixedUnsigned(0))
    elif item.kind == "digest":
        var decoded = decode_digest_borrowed(Span(item.wire), ByteLimit(1048576))
        require(decoded.isa[Decoded[WorkDigest]]())
        var value = decoded[Decoded[WorkDigest]].copy()
        require(value.consumed == size)
        item.digest = value.value.copy()
    elif item.kind == "blake2b":
        var hashed = blake2b256(Span(item.wire))
        require(hashed.isa[Blake2bHash]())
        var value = hashed[Blake2bHash].copy()
        print("HASH", hex_text(Span(value.bytes)))
    else:
        # An unknown trusted case cannot silently benchmark a different production API.
        require(False)
    if item.operation == "owned-encode":
        var schema = 4
        if item.kind == "blob":
            # Prepared byte-string snapshots carry their own exact schema identity.
            schema = 0
        var result = capture(
            Span(item.wire),
            schema,
            ByteLimit(1048576),
            PreimageLimits(ElementLimit(0), ByteLimit(0), ByteLimit(0)),
        )
        require(result.isa[OwnedFrame]())
        item.owner = result[OwnedFrame].copy()
    print("VERIFY", step(item))
    if item.kind in ("blob", "sequence", "digest") and item.operation in ("encode", "owned-encode"):
        for i in range(size):
            # Check the whole native reconstructed input before accepting any throughput or latency samples.
            require(item.output[i] == item.wire[i])
    return item^


# Report native batch/individual timestamps separately from public allocator-delta observations.
def main() raises:
    var args = argv()
    require(len(args) == 7)
    var item = prepare(String(args[1]), String(args[2]), String(args[3]))
    try:
        var iterations = capacity(String(args[4]), 20000000)
        var samples = capacity(String(args[5]), 31)
        var latency_samples = capacity(String(args[6]), 256)
        require(iterations >= 1 and samples >= 1)
        var checksum: UInt64 = 0
        for _ in range(min(iterations, 64)):
            # Warm runtime/allocator/code paths before either timing or allocation observation begins.
            checksum ^= step(item)
        comptime if ALLOCATIONS:
            var before = external_call["rqm_heap_used", UInt64]()
            for _ in range(iterations):
                # This separate binary reports actual process malloc live delta, never invented allocation call counts.
                checksum ^= step(item)
            var after = external_call["rqm_heap_used", UInt64]()
            print("ALLOC_MOJO_HEAP", iterations, Int(after) - Int(before))
        else:
            for _ in range(samples):
                var started = external_call["rb_now_ns", UInt64]()
                for _ in range(iterations):
                    # Batches amortize timer overhead while preserving identical operation counts across candidates.
                    checksum ^= step(item)
                var elapsed = external_call["rb_now_ns", UInt64]() - started
                print("BATCH", iterations, elapsed)
            var latencies = List[UInt64](length=latency_samples, fill=0)
            for i in range(latency_samples):
                var started = external_call["rb_now_ns", UInt64]()
                checksum ^= step(item)
                latencies[i] = UInt64(external_call["rb_now_ns", UInt64]() - started)
            for i in range(latency_samples):
                # True single-operation latency samples include the same timer/observer overhead as the other candidates.
                print("LATENCY", latencies[i])
        print("END", checksum, external_call["rb_peak_rss", UInt64]())
    finally:
        # Prepared snapshot ownership retires after all measured calls; per-operation captures already release inside step.
        release(item.owner)
