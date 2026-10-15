from std.collections import Array, Span
from std.ffi import external_call, c_size_t
from std.sys import argv, size_of, get_defined_bool
from codec.types import *
from codec.report import *
from codec.report_owned import *
from crypto.primitives import EdPublicKey, EdSignature, import_public, import_signature, verify
from crypto.guarantee import GuaranteeMessage, guarantee_message
from tests.support import unhex, hex_text, capacity


comptime REPORT_ALLOCATIONS = get_defined_bool["REPORT_ALLOCATIONS", False]()


# Prepared stable input, typed encoder fields and public credentials remain alive across all timed calls.
@fieldwise_init
struct ReportCase(Movable):
    var mode: String
    var wire: List[UInt8]
    var output: List[UInt8]
    var report: WorkReport
    var message: GuaranteeMessage
    var keys: Array[EdPublicKey, 2]
    var signatures: Array[EdSignature, 2]


# Trusted benchmark invariants fail visibly, while production malformed-input APIs retain tagged failures.
def bench_require(good: Bool):
    if not good:
        # A rejected preflight or operation cannot generate a successful timing record.
        external_call["abort", NoneType]()


# Keep complete result storage observable through the common separately compiled non-LTO boundary.
def report_observe[T: AnyType](ref value: T):
    external_call["rb_observe", NoneType](
        Pointer(to=value).unsafe_bitcast[NoneType]().as_imm().as_unsafe_any_origin(),
        c_size_t(size_of[T]()),
    )


# Both ordinary-key credentials are checked even when the first fails; backend policy remains unchanged.
def report_verify(item: ReportCase, message: Span[mut=False, UInt8, _]) -> Bool:
    var first = verify(item.keys[0], item.signatures[0], message)
    var second = verify(item.keys[1], item.signatures[1], message)
    return first and second


# One real runtime-input API operation; file I/O, fixture imports and formatting stay outside timing.
@no_inline
def report_step(mut item: ReportCase) -> UInt64:
    if item.mode == "decode":
        # Observe the complete decoded report so unused fields cannot be optimized to a small fingerprint.
        var decoded = decode_report_borrowed(Span(item.wire), UInt64(341))
        bench_require(decoded.isa[Decoded[WorkReport]]())
        bench_require(decoded[Decoded[WorkReport]].consumed == len(item.wire))
        report_observe(decoded)
    elif item.mode == "encode":
        # Prepared metadata excludes an untimed hidden decode; ordinary report preflight remains enabled.
        var written = encode_report_borrowed(
            item.report.copy(), Span(item.wire), UInt64(341), Span(item.output)
        )
        bench_require(written.isa[Written]() and written[Written].written == len(item.wire))
        external_call["rb_observe", NoneType](
            item.output.unsafe_ptr().as_imm().as_unsafe_any_origin(), c_size_t(len(item.output))
        )
    elif item.mode == "owned" or item.mode == "pipeline":
        # Capture, re-emission and exactly one final release all belong to the measured operation lifetime.
        var captured = decode_owned_report(Span(item.wire), UInt64(341))
        bench_require(captured.isa[OwnedReport]())
        var owner = captured[OwnedReport].copy()
        var written = encode_owned_report(owner, Span(item.output))
        bench_require(written.isa[Written]() and written[Written].written == len(item.wire))
        external_call["rb_observe", NoneType](
            item.output.unsafe_ptr().as_imm().as_unsafe_any_origin(), c_size_t(len(item.output))
        )
        if item.mode == "pipeline":
            # Exact owned canonical bytes feed the normative domain/hash and two-credential verification.
            var message = guarantee_message(Span(item.output))
            bench_require(message.isa[GuaranteeMessage]())
            var bytes = message[GuaranteeMessage].copy()
            bench_require(report_verify(item, Span(bytes.bytes)))
            report_observe(bytes)
        release_report(owner)
    elif item.mode == "hash":
        # Provider hashing and native normative domain composition are measured together.
        var message = guarantee_message(Span(item.wire))
        bench_require(message.isa[GuaranteeMessage]())
        report_observe(message)
    elif item.mode == "verify2":
        # Prepared message excludes report hashing so actual provider verification cost is visible separately.
        var valid = report_verify(item, Span(item.message.bytes))
        bench_require(valid)
        report_observe(valid)
    else:
        # No unknown mode may silently become a no-work successful benchmark.
        bench_require(False)
    return UInt64(len(item.wire))


# Preflight full wire/message/verdict bytes, then produce bounded native batch/latency or allocation observations.
def report_benchmark() raises:
    var args = argv()
    bench_require(len(args) == 11)
    var wire: List[UInt8]
    with open(args[3], "r") as file:
        wire = file.read_bytes()
    bench_require(len(wire) <= 65536)
    var parsed = decode_report_borrowed(Span(wire), UInt64(341))
    bench_require(
        parsed.isa[Decoded[WorkReport]]() and parsed[Decoded[WorkReport]].consumed == len(wire)
    )
    var output = List[UInt8](length=len(wire), fill=0)
    var written = encode_report_borrowed(
        parsed[Decoded[WorkReport]].value.copy(), Span(wire), UInt64(341), Span(output)
    )
    bench_require(written.isa[Written]() and written[Written].written == len(wire))
    # Every encoded byte must match independent corpus bytes before any timing can be accepted.
    for i in range(len(wire)):
        bench_require(output[i] == wire[i])
    var key_bytes = unhex(String(args[4]))
    var signature_bytes = unhex(String(args[5]))
    var public = import_public(Span(key_bytes))
    var signed = import_signature(Span(signature_bytes))
    bench_require(public.isa[EdPublicKey]() and signed.isa[EdSignature]())
    var message = guarantee_message(Span(wire))
    bench_require(message.isa[GuaranteeMessage]())
    var item = ReportCase(
        String(args[2]),
        wire^,
        output^,
        parsed[Decoded[WorkReport]].value.copy(),
        message[GuaranteeMessage].copy(),
        Array[EdPublicKey, 2](fill=public[EdPublicKey].copy()),
        Array[EdSignature, 2](fill=signed[EdSignature].copy()),
    )
    var second_key_bytes = unhex(String(args[6]))
    var second_signature_bytes = unhex(String(args[7]))
    var second_public = import_public(Span(second_key_bytes))
    var second_signed = import_signature(Span(second_signature_bytes))
    bench_require(second_public.isa[EdPublicKey]() and second_signed.isa[EdSignature]())
    item.keys[1] = second_public[EdPublicKey].copy()
    item.signatures[1] = second_signed[EdSignature].copy()
    var valid = report_verify(item, Span(item.message.bytes))
    print("VERIFY", hex_text(Span(item.output)), hex_text(Span(item.message.bytes)), Int(valid))
    if item.mode == "check":
        # Negative credentials are verified explicitly without entering timing loops.
        return
    bench_require(valid)
    var iterations = capacity(String(args[8]), 20000000)
    var samples = capacity(String(args[9]), 31)
    var latency = capacity(String(args[10]), 256)
    bench_require(iterations >= 1 and samples >= 1)
    var checksum: UInt64 = 0
    # Warm allocator, provider, SDK and code paths before either type of observation.
    for _ in range(min(iterations, 64)):
        checksum ^= report_step(item)
    comptime if REPORT_ALLOCATIONS:
        # Public malloc delta includes the SDK/provider; it is not an invented allocation-call counter.
        var before = external_call["rqm_heap_used", UInt64]()
        for _ in range(iterations):
            checksum ^= report_step(item)
        var after = external_call["rqm_heap_used", UInt64]()
        print("ALLOC_MOJO_HEAP", iterations, Int(after) - Int(before))
    else:
        # Native batches amortize the same independently compiled clock implementation in every language.
        for _ in range(samples):
            var start = external_call["rb_now_ns", UInt64]()
            for _ in range(iterations):
                # Identical per-operation work remains inside a no-inline boundary.
                checksum ^= report_step(item)
            print("BATCH", iterations, external_call["rb_now_ns", UInt64]() - start)
        var latencies = List[UInt64](length=latency, fill=0)
        for i in range(latency):
            # One call per sample includes shared timer/observer overhead, unlike amortized batch averages.
            var start = external_call["rb_now_ns", UInt64]()
            checksum ^= report_step(item)
            latencies[i] = external_call["rb_now_ns", UInt64]() - start
        for elapsed in latencies:
            # Formatting cannot enter the measured single-operation interval.
            print("LATENCY", elapsed)
    print("END", checksum, external_call["rb_peak_rss", UInt64]())
