from std.collections import Array, Span, Optional
from std.sys import argv
from codec.types import *
from codec.scalar import *
from codec.composite import *
from codec.digest import *
from codec.report import *
from codec.report_owned import *
from codec.owned import OwnedDigestInfo, OwnedPresent
from tests.support import unsigned, capacity, hex_text, unchanged
from tests.report_bench import report_benchmark


# Fail trusted adapter invariants visibly; malformed production inputs return ordinary tagged failures.
def require(good: Bool) raises:
    if not good:
        # A failed invariant must never be reported as an ordinary passing codec request.
        raise Error("complete-report adapter invariant")


# Decode bounded lowercase hex; dash denotes an explicit empty adapter payload.
def report_unhex(text: String) raises -> List[UInt8]:
    var result = List[UInt8]()
    # Preserve empty payload tokens even between other whitespace-separated fields.
    if text == "-":
        return result^
    var chars = text.as_bytes()
    # No input-derived allocation may exceed the adapter's established 64-KiB capacity.
    if len(chars) % 2 != 0 or len(chars) > 131072:
        raise Error("hex length")
    # Validate both nibbles before appending each complete byte.
    for i in range(len(chars) // 2):
        var value = 0
        # The protocol accepts only lowercase hexadecimal digits.
        for j in range(2):
            var c = Int(chars[2 * i + j])
            var digit = c - 48
            # Lowercase letters map to the remaining hexadecimal digits.
            if c >= 97 and c <= 102:
                digit = c - 87
            elif c < 48 or c > 57:
                # Invalid request text never reaches a production codec.
                raise Error("hex digit")
            value = value * 16 + digit
        result.append(UInt8(value))
    return result^


# Render named fixed fields independently of the production header encoder to catch swapped-field bugs.
def header_bytes(value: ReportHeader) -> Array[UInt8, 234]:
    var result = Array[UInt8, 234](fill=0)
    # Inspect the declared package_hash domain independently of codec field layout.
    for i in range(32):
        result[0 + i] = value.package_hash.bytes[i]
    # Inspect the declared bundle_length domain independently of codec field layout.
    for i in range(4):
        result[32 + i] = UInt8((UInt64(value.bundle_length.value) >> UInt64(8 * i)) & 255)
    # Inspect the declared erasure_root domain independently of codec field layout.
    for i in range(32):
        result[36 + i] = value.erasure_root.bytes[i]
    # Inspect the declared segment_root domain independently of codec field layout.
    for i in range(32):
        result[68 + i] = value.segment_root.bytes[i]
    # Inspect the declared segment_count domain independently of codec field layout.
    for i in range(2):
        result[100 + i] = UInt8((UInt64(value.segment_count.value) >> UInt64(8 * i)) & 255)
    # Inspect the declared anchor domain independently of codec field layout.
    for i in range(32):
        result[102 + i] = value.anchor.bytes[i]
    # Inspect the declared state_root domain independently of codec field layout.
    for i in range(32):
        result[134 + i] = value.state_root.bytes[i]
    # Inspect the declared accumulation_root domain independently of codec field layout.
    for i in range(32):
        result[166 + i] = value.accumulation_root.bytes[i]
    # Inspect the declared lookup_anchor domain independently of codec field layout.
    for i in range(32):
        result[198 + i] = value.lookup_anchor.bytes[i]
    # Inspect the declared lookup_slot domain independently of codec field layout.
    for i in range(4):
        result[230 + i] = UInt8((UInt64(value.lookup_slot.value) >> UInt64(8 * i)) & 255)
    return result^


# Print every decoded field; exact child reconstruction uses the separately verified existing digest codec.
def print_report(value: WorkReport, wire: Span[mut=False, UInt8, _], consumed: Int) raises:
    var header = header_bytes(value.header)
    var prerequisites = List[UInt8](length=32 * value.prerequisite_count, fill=0)
    # Preserve all ordered prerequisite bytes, rather than checking cardinality alone.
    for i in range(value.prerequisite_count):
        for j in range(32):
            # Each declared member is copied into its independently sized output token.
            prerequisites[32 * i + j] = value.prerequisites[i].bytes[j]
    var lookup = List[UInt8](length=64 * value.lookup_count, fill=0)
    # Both dictionary keys and their associated roots are visible to the independent oracle.
    for i in range(value.lookup_count):
        for j in range(32):
            # Complete pairs retain wire identity order without implicit hashing.
            lookup[64 * i + j] = value.lookup[i].package_hash.bytes[j]
            lookup[64 * i + 32 + j] = value.lookup[i].segment_root.bytes[j]
    var digests = List[UInt8](length=65536, fill=0)
    var cursor = 0
    # Every child is reconstructed from typed fields and original whole-input payload coordinates.
    for i in range(value.digest_count):
        var written = encode_digest_borrowed(
            value.digests[i].value().copy(), wire, ByteLimit(49152), Span(digests)[cursor:]
        )
        require(written.isa[Written]())
        cursor += written[Written].written
    print(
        hex_text(Span(header))
        + " "
        + hex_text(Span(prerequisites))
        + " "
        + String(value.core.value)
        + " "
        + hex_text(Span(value.authorizer.bytes))
        + " "
        + String(value.auth_gas.value)
        + " "
        + hex_text(
            wire[value.auth_output.offset : value.auth_output.offset + value.auth_output.length]
        )
        + " "
        + hex_text(Span(lookup))
        + " "
        + hex_text(Span(digests)[:cursor])
        + " "
        + String(value.digest_count)
        + " "
        + String(consumed)
    )


# Trusted construction retains a typed value and its exact backing pool, without using the new report decoder.
@fieldwise_init
struct Constructed(Movable):
    var value: WorkReport
    var pool: List[UInt8]


# Construct report fields from the independent oracle representation; only existing child digest parsing is reused.
def build_report(p: List[String]) raises -> Constructed:
    var fixed = report_unhex(p[3])
    require(len(fixed) == 234)
    var header = decode_report_header(Span(fixed))
    require(header.isa[ReportHeader]())
    var value = empty_report(header[ReportHeader].copy())
    var prerequisites = report_unhex(p[4])
    var authorizer = report_unhex(p[6])
    var auth = report_unhex(p[8])
    var lookup = report_unhex(p[9])
    var digests = report_unhex(p[10])
    require(
        len(prerequisites) % 32 == 0
        and len(prerequisites) <= 256
        and len(authorizer) == 32
        and len(lookup) % 64 == 0
        and len(lookup) <= 512
        and len(auth) + len(digests) <= 65536
    )
    value.prerequisite_count = len(prerequisites) // 32
    value.lookup_count = len(lookup) // 64
    value.core = CoreIndex(unsigned(p[5]))
    value.auth_gas = Gas(unsigned(p[7]))
    value.digest_count = capacity(p[11], 16)
    require(value.digest_count >= 1)
    # Trusted text still validates exact domain widths and metadata capacities before indexing.
    for i in range(32):
        value.authorizer.bytes[i] = authorizer[i]
    for i in range(value.prerequisite_count):
        # Each full hash belongs to the previously checked fixed-stride source.
        for j in range(32):
            value.prerequisites[i].bytes[j] = prerequisites[32 * i + j]
    for i in range(value.lookup_count):
        # Construct independent key/root fields without a work-report decode.
        for j in range(32):
            value.lookup[i].package_hash.bytes[j] = lookup[64 * i + j]
            value.lookup[i].segment_root.bytes[j] = lookup[64 * i + 32 + j]
    var pool = List[UInt8](length=len(auth) + len(digests), fill=0)
    Span(pool)[: len(auth)].copy_from(Span(auth))
    Span(pool)[len(auth) :].copy_from(Span(digests))
    value.auth_output = BlobSpan(0, len(auth))
    var cursor = len(auth)
    # Existing digest parsing supplies typed child values; the new report codec is not involved.
    for i in range(value.digest_count):
        var parsed = decode_digest_borrowed(Span(pool)[cursor:], ByteLimit(49152))
        require(parsed.isa[Decoded[WorkDigest]]())
        var child = parsed[Decoded[WorkDigest]].copy()
        var digest = child.value.copy()
        if digest.output.isa[BlobSpan]():
            # Rebase child payloads into the single retained construction pool.
            var blob = digest.output[BlobSpan].copy()
            digest.output = WorkOutput(BlobSpan(cursor + blob.offset, blob.length))
        value.digests[i] = Optional[WorkDigest](digest^)
        cursor += child.consumed
    require(cursor == len(pool))
    return Constructed(value^, pool^)


# Check retained complete bytes and owner-bound payload extraction after the caller mutates its input.
def check_owner(mut wire: List[UInt8], value: WorkReport, consumed: Int, cores: UInt64) raises:
    var captured = decode_owned_report(Span(wire), cores)
    require(captured.isa[OwnedReport]())
    var owner = captured[OwnedReport].copy()
    try:
        var info = owned_report_info(owner)
        require(info.isa[OwnedReportInfo]())
        require(
            info[OwnedReportInfo].consumed == consumed
            and info[OwnedReportInfo].digest_count == value.digest_count
            and info[OwnedReportInfo].core.value == value.core.value
            and info[OwnedReportInfo].auth_gas.value == value.auth_gas.value
        )
        # Owner metadata preserves exact fixed fields, dependency identities and all digest metrics.
        var info_header = header_bytes(info[OwnedReportInfo].header)
        var expected_header = header_bytes(value.header)
        require(hex_text(Span(info_header)) == hex_text(Span(expected_header)))
        require(
            info[OwnedReportInfo].prerequisite_count == value.prerequisite_count
            and info[OwnedReportInfo].lookup_count == value.lookup_count
        )
        for i in range(value.prerequisite_count):
            var item = owned_report_prerequisite(owner, i)
            require(item.isa[PackageHash]())
            for j in range(32):
                # Every copied identity byte must match the typed borrowed decode.
                require(item[PackageHash].bytes[j] == value.prerequisites[i].bytes[j])
        for i in range(value.lookup_count):
            var item = owned_report_lookup(owner, i)
            require(item.isa[SegmentLookup]())
            for j in range(32):
                # Key and root domains remain independently visible in copied metadata.
                require(
                    item[SegmentLookup].package_hash.bytes[j]
                    == value.lookup[i].package_hash.bytes[j]
                )
                require(
                    item[SegmentLookup].segment_root.bytes[j]
                    == value.lookup[i].segment_root.bytes[j]
                )
        for i in range(value.digest_count):
            var item = owned_report_digest(owner, i)
            require(item.isa[OwnedDigestInfo]())
            var digest = item[OwnedDigestInfo].copy()
            var expected = value.digests[i].value().copy()
            require(
                digest.service.value == expected.service.value
                and digest.accumulate_gas.value == expected.accumulate_gas.value
            )
            for j in range(32):
                # Fixed hashes are values, never caller-mutable references into retained bytes.
                require(
                    digest.code_hash.bytes[j] == expected.code_hash.bytes[j]
                    and digest.payload_hash.bytes[j] == expected.payload_hash.bytes[j]
                )
            if expected.output.isa[BlobSpan]():
                # Success metadata exposes only a length, retaining payload extraction at the owner boundary.
                require(
                    digest.output.isa[OwnedPresent]()
                    and digest.output[OwnedPresent].length == expected.output[BlobSpan].length
                )
            else:
                require(
                    digest.output.isa[WorkFailure]()
                    and digest.output[WorkFailure].tag == expected.output[WorkFailure].tag
                )
            var actual_metrics = metrics(digest.refine)
            var expected_metrics = metrics(expected.refine)
            for j in range(5):
                # Late refinement metrics are part of the complete owned digest, not discarded parser data.
                require(actual_metrics[j] == expected_metrics[j])
        var bad_prerequisite = owned_report_prerequisite(owner, value.prerequisite_count)
        var bad_lookup = owned_report_lookup(owner, value.lookup_count)
        var bad_digest = owned_report_digest(owner, value.digest_count)
        require(
            bad_prerequisite.isa[Failure]()
            and bad_lookup.isa[Failure]()
            and bad_digest.isa[Failure]()
        )
        var missing = owned_report_info(OwnedReport(None))
        require(missing.isa[Failure]() and missing[Failure].reason() == "invalidowner")
        var output = List[UInt8](length=65536, fill=77)
        var original = wire.copy()
        # Mutate the complete input, including payload bytes and unrelated trailing data.
        for i in range(len(wire)):
            wire[i] = 99
        var encoded = encode_owned_report(owner, Span(output))
        require(encoded.isa[Written]() and encoded[Written].written == consumed)
        require(output[0] == original[0])
        # Retained snapshots reproduce the consumed prefix alone, never unrelated trailing bytes.
        for i in range(consumed):
            require(output[i] == original[i])
        var payload = List[UInt8](length=65536, fill=77)
        # The API's zero index selects authorization output; each subsequent index selects one digest.
        for index in range(value.digest_count + 1):
            var blob = value.auth_output.copy()
            var has_blob = True
            if index > 0:
                # Work errors have no extractable payload and must not appear as empty success blobs.
                var digest = value.digests[index - 1].value().copy()
                if digest.output.isa[BlobSpan]():
                    blob = digest.output[BlobSpan].copy()
                else:
                    has_blob = False
            var copied = copy_report_blob(owner, index, Span(payload))
            if has_blob:
                # Owner binding must preserve every byte after source mutation.
                require(copied.isa[Written]() and copied[Written].written == blob.length)
                for i in range(blob.length):
                    require(payload[i] == original[blob.offset + i])
            else:
                # Payload-free protocol errors reject extraction explicitly.
                require(copied.isa[Failure]() and copied[Failure].reason() == "invalidindex")
        output = List[UInt8](length=65536, fill=77)
        var small = encode_owned_report(owner, Span(output)[: consumed - 1])
        require(small.isa[Failure]() and small[Failure].reason() == "outputtoosmall")
        unchanged(Span(output))
        var bad_index = copy_report_blob(owner, -1, Span(payload))
        require(bad_index.isa[Failure]() and bad_index[Failure].reason() == "invalidindex")
        # Restore borrowed input for independent field inspection after the owner checks.
        for i in range(len(wire)):
            wire[i] = original[i]
    finally:
        # Exactly one original owner retires storage; captured/result copies are borrowed handle aliases.
        release_report(owner)


# Exercise late encoder failures and whole-pool overlap; any partial write is a test failure.
def mutation(kind: String, mut wire: List[UInt8], cores: UInt64) raises:
    var decoded = decode_report_borrowed(Span(wire), cores)
    require(decoded.isa[Decoded[WorkReport]]())
    var value = decoded[Decoded[WorkReport]].value.copy()
    var output = List[UInt8](length=65536, fill=77)
    if kind == "span":
        # Last-child descriptor failure must not commit even the first header byte.
        var digest = value.digests[value.digest_count - 1].value().copy()
        digest.output = WorkOutput(BlobSpan(len(wire), 1))
        value.digests[value.digest_count - 1] = Optional[WorkDigest](digest^)
    elif kind == "count":
        # A work report cannot contain zero work digests.
        value.digest_count = 0
    elif kind == "tag":
        # Public WorkFailure construction must still reject unsupported tags during encode preflight.
        var digest = value.digests[value.digest_count - 1].value().copy()
        digest.output = WorkOutput(WorkFailure(255))
        value.digests[value.digest_count - 1] = Optional[WorkDigest](digest^)
    elif kind == "core":
        # The first out-of-range configured core must be rejected without narrowing.
        value.core = CoreIndex(cores)
    elif kind == "alias":
        # Explicit unsafe provenance is necessary to manufacture overlap past the language borrow checker.
        var saved = wire.copy()
        var pool = Span(
            unsafe_ptr=wire.unsafe_ptr().as_imm().as_unsafe_any_origin(), length=len(wire)
        )
        var encoded = encode_report_borrowed(value.copy(), pool, cores, Span(wire))
        require(encoded.isa[Failure]() and encoded[Failure].reason() == "aliasedbuffers")
        for i in range(len(wire)):
            # The complete caller pool must survive failed overlap preflight unchanged.
            require(wire[i] == saved[i])
        print(encoded[Failure].reason())
        return
    else:
        # Unregistered adapter operations are harness errors, not decoder outcomes.
        raise Error("mutation kind")
    var encoded = encode_report_borrowed(value.copy(), Span(wire), cores, Span(output))
    require(encoded.isa[Failure]())
    unchanged(Span(output))
    print(encoded[Failure].reason())


# Process the identical trusted file protocol using only native Mojo runtime facilities.
def main() raises:
    var args = argv()
    # Select measurements before parsing conformance utility requests.
    if len(args) > 1 and args[1] == "bench":
        report_benchmark()
        return
    require(len(args) == 2)
    var text: String
    with open(args[1], "r") as file:
        text = file.read()
    var lines = text.split("\n")
    # Every nonempty request has one response; no Python implementation runs inside the native binary.
    for index in range(len(lines)):
        var line = String(lines[index])
        if line == "":
            # The file-final newline does not describe a codec operation.
            continue
        var parts = line.split(" ")
        var p = List[String]()
        for i in range(len(parts)):
            # Own textual tokens for the duration of their synchronous native calls.
            p.append(String(parts[i]))
        require(len(p) == 3 or len(p) == 4 or len(p) == 12)
        var cores = unsigned(p[1])
        if p[0] == "D" and len(p) == 3:
            # Decode malformed external bytes through the ordinary failure-only production API.
            var wire = report_unhex(p[2])
            var parsed = decode_report_borrowed(Span(wire), cores)
            if parsed.isa[Failure]():
                print(parsed[Failure].reason())
            else:
                # Complete success alone enables owned capture and field access.
                var value = parsed[Decoded[WorkReport]].copy()
                check_owner(wire, value.value.copy(), value.consumed, cores)
                var output = List[UInt8](length=65536, fill=77)
                var encoded = encode_report_borrowed(
                    value.value.copy(), Span(wire), cores, Span(output)
                )
                require(encoded.isa[Written]() and encoded[Written].written == value.consumed)
                for i in range(value.consumed):
                    # Every field and final metric must round-trip the exact consumed prefix.
                    require(output[i] == wire[i])
                print_report(value.value.copy(), Span(wire), value.consumed)
        elif p[0] == "E" and len(p) == 12:
            # Independent source-field construction avoids using the new report decoder as an encoding oracle.
            var built = build_report(p.copy())
            var cap = capacity(p[2], 65536)
            var output = List[UInt8](length=65536, fill=77)
            var encoded = encode_report_borrowed(
                built.value.copy(), Span(built.pool), cores, Span(output)[:cap]
            )
            if encoded.isa[Written]():
                print(hex_text(Span(output)[: encoded[Written].written]))
            else:
                # Failed writes must leave the entire destination, including unused capacity, unchanged.
                unchanged(Span(output))
                print(encoded[Failure].reason())
        elif p[0] == "X" and len(p) == 4:
            # Native misuse probes validate late failures and the complete borrowed-pool overlap contract.
            var wire = report_unhex(p[3])
            mutation(p[2], wire, cores)
        else:
            # Harness protocol drift must not silently become a different production operation.
            raise Error("report command")
