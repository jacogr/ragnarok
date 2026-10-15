from std.collections import Span, Array
from std.sys import argv
from codec.types import *
from codec.scalar import *
from codec.bounded import *
from codec.composite import *
from codec.digest import *
from tests.support import *
from tests.ownership_checks import check_capture


# Print completed encoder bytes or a failure, asserting atomicity of the full destination on errors.
def print_write(var result: WriteResult, data: Span[mut=False, UInt8, _]) raises:
    # Only the completed branch exposes an output extent.
    if result.isa[Written]():
        print(hex_text(data[: result[Written].written]))
    else:
        # Every byte, including unused capacity, must retain its sentinel on failure.
        unchanged(data)
        print(result[Failure].reason())


# Exercise the independent scalar production APIs over the exact shared batch protocol.
def scalar_request(p: List[String], fixed: Bool) raises:
    # Natural encode uses the nominal domain and owns bounded local output.
    if not fixed and len(p) == 2 and p[0] == "E":
        var encoded = encode_natural(JamNatural(unsigned(p[1])))
        print(hex_text(Span(encoded.bytes)[: encoded.length], False))
    elif not fixed and len(p) == 2 and p[0] == "D":
        # Primitive adapters use empty text rather than dash in a few truncation cases.
        var data = unhex(p[1])
        var result = decode_natural(Span(data))
        # Never access value or consumed fields of the failure alternative.
        if result.isa[Failure]():
            print(result[Failure].reason())
        else:
            var value = result[Decoded[JamNatural]].copy()
            print(String(value.value.value) + " " + String(value.consumed))
    elif fixed and len(p) == 3 and p[0] == "FE":
        # Signed widths and UInt64 values are validated independently.
        var result = encode_fixed(FixedUnsigned(unsigned(p[2])), ByteWidth(signed(p[1])))
        # Only a completed fixed encoding exposes bytes.
        if result.isa[Failure]():
            print(result[Failure].reason())
        else:
            var value = result[Encoded].copy()
            print(hex_text(Span(value.bytes)[: value.length], False))
    elif fixed and len(p) == 3 and p[0] == "FD":
        # Trailing data remains borrowed, outside the selected prefix.
        var data = unhex(p[2])
        var result = decode_fixed(Span(data), ByteWidth(signed(p[1])))
        # Failed widths and truncations carry no default numeric value.
        if result.isa[Failure]():
            print(result[Failure].reason())
        else:
            var value = result[Decoded[FixedUnsigned]].copy()
            print(String(value.value.value) + " " + String(value.consumed))
    else:
        # Wrong command/arity stays in the trusted utility layer.
        print("inputerror")


# Route bounded requests and assert both encoder and typed-decoder atomic failure contracts.
def bounded_request(p: List[String]) raises:
    # Byte encoding has separate policy and actual destination capacity.
    if len(p) == 4 and p[0] == "BE":
        var value = unhex(p[3])
        var output = List[UInt8](length=capacity(p[2], 32768), fill=77)
        print_write(
            encode_bytes(Span(value), ByteLimit(unsigned(p[1])), Span(output)), Span(output)
        )
    elif len(p) == 3 and p[0] == "BD":
        # Successful blob coordinates refer to this retained native local owner.
        var wire = unhex(p[2])
        var result = decode_bytes_borrowed(Span(wire), ByteLimit(unsigned(p[1])))
        # Failed blob decoding cannot expose a span.
        if result.isa[Failure]():
            print(result[Failure].reason())
        else:
            var value = result[Decoded[BlobSpan]].copy()
            check_capture(
                wire,
                0,
                ByteLimit(unsigned(p[1])),
                PreimageLimits(ElementLimit(0), ByteLimit(0), ByteLimit(0)),
                value.consumed,
            )
            print(
                hex_text(Span(wire)[value.value.offset : value.value.offset + value.value.length])
                + " "
                + String(value.consumed)
            )
    elif len(p) == 5 and p[0] == "SE":
        # Textual lists have an explicit empty token and a separate utility element bound.
        var values = List[FixedUnsigned]()
        if p[4] != "-":
            var numbers = p[4].split(",")
            # Never allocate arbitrary input-derived typed storage in the adapter.
            if len(numbers) > 512:
                raise Error("elements")
            # Preserve each full unsigned value before production width validation.
            for i in range(len(numbers)):
                values.append(FixedUnsigned(unsigned(String(numbers[i]))))
        var output = List[UInt8](length=capacity(p[3], 32768), fill=77)
        print_write(
            encode_sequence(
                Span(values), ByteWidth(signed(p[1])), ElementLimit(unsigned(p[2])), Span(output)
            ),
            Span(output),
        )
    elif len(p) == 5 and p[0] == "SD":
        # Typed destination capacity is independent from the count claimed on the wire.
        var wire = unhex(p[4])
        var values = List[FixedUnsigned](length=capacity(p[3], 512), fill=FixedUnsigned(999))
        var result = decode_sequence(
            Span(wire), ByteWidth(signed(p[1])), ElementLimit(unsigned(p[2])), Span(values)
        )
        # No rejected frame may modify any element of caller storage.
        if result.isa[Failure]():
            # Check all sentinels before reporting the ordinary codec error.
            for i in range(len(values)):
                # A changed element indicates a decoder implementation bug, not malformed input.
                if values[i].value != 999:
                    raise Error("partial typed commit")
            print(result[Failure].reason())
        else:
            # Report only the proven initialized prefix.
            var count = result[SequenceInfo].count
            var text = String()
            for i in range(count):
                # Separators belong only between values, never at the end.
                if i != 0:
                    text += ","
                text += String(values[i].value)
            # Preserve the explicit empty-list response token.
            if count == 0:
                text = "-"
            print(text + " " + String(result[SequenceInfo].consumed))
    else:
        # Unknown requests never accidentally invoke a production decoder.
        print("inputerror")


# Exercise optional/work/preimage APIs through the identical existing composite batch protocol.
def composite_request(p: List[String]) raises:
    var output = List[UInt8](length=32768, fill=77)
    # Trusted encoder discriminators select nominal tagged branches after textual validation.
    if len(p) == 5 and (p[0] == "OE" or p[0] == "WE"):
        var tag = signed(p[1])
        var limit = ByteLimit(unsigned(p[2]))
        var cap = capacity(p[3], 32768)
        var pool = unhex(p[4])
        # Optional presence permits only zero and one.
        if p[0] == "OE":
            # Invalid textual presence is an adapter error, never a fabricated typed value.
            if tag < 0 or tag > 1:
                raise Error("presence")
            var value = OptionalBlob(Absent())
            # Only a present optional borrows the pool.
            if tag == 1:
                value = OptionalBlob(BlobSpan(0, len(pool)))
            print_write(
                encode_optional_borrowed(value^, Span(pool), limit, Span(output)[:cap]),
                Span(output),
            )
        else:
            # Reject out-of-schema work tags before unsigned conversion.
            if tag < 0 or tag > 6:
                print("invalidtag")
                return
            var value = WorkOutput(WorkFailure(UInt64(tag)))
            # Successful work output is the only blob-bearing alternative.
            if tag == 0:
                value = WorkOutput(BlobSpan(0, len(pool)))
            print_write(
                encode_work_borrowed(value^, Span(pool), limit, Span(output)[:cap]), Span(output)
            )
    elif len(p) == 3 and (p[0] == "OD" or p[0] == "WD"):
        # The local wire owner remains stable throughout decode and independent re-encoding.
        var limit = ByteLimit(unsigned(p[1]))
        var wire = unhex(p[2])
        var maximum: UInt64 = 6
        var blob_tag: UInt64 = 0
        # The optional schema uses one as its payload discriminator.
        if p[0] == "OD":
            maximum = 1
            blob_tag = 1
        var result = read_tag(Span(wire), maximum, blob_tag, limit)
        # Bad tags/lengths expose no usable coordinates.
        if result.isa[Failure]():
            print(result[Failure].reason())
            return
        var parsed = result[Tagged].copy()
        var kind = 2
        # Optional and work frames retain their distinct owned schema identifiers.
        if p[0] == "OD":
            kind = 1
        check_capture(
            wire,
            kind,
            limit,
            PreimageLimits(ElementLimit(0), ByteLimit(0), ByteLimit(0)),
            parsed.consumed,
        )
        var encoded = write_tag(
            parsed.tag, parsed.tag == blob_tag, parsed.blob, Span(wire), limit, Span(output)
        )
        # Reconstruction must reproduce only the consumed prefix, excluding trailing fields.
        if not encoded.isa[Written]() or encoded[Written].written != parsed.consumed:
            raise Error("composite reconstruction extent")
        # Check each emitted byte against the retained original frame.
        for i in range(parsed.consumed):
            # Divergence is a production codec bug and must stop conformance testing.
            if output[i] != wire[i]:
                raise Error("composite reconstruction bytes")
        var text = String(parsed.tag) + ":-"
        # Optional absence contains no payload field.
        if p[0] == "OD" and parsed.tag == 0:
            text = "absent"
        elif parsed.tag == blob_tag:
            # Select exactly the validated payload, using original input coordinates.
            text = hex_text(
                Span(wire)[parsed.blob.offset : parsed.blob.offset + parsed.blob.length]
            )
            # Preserve the established language-independent response labels.
            if p[0] == "OD":
                text = "present:" + text
            else:
                text = "0:" + text
        print(text + " " + String(parsed.consumed))
    elif len(p) == 6 and (p[0] == "PE" or p[0] == "PD"):
        # Three policies independently bound tuple count, each blob and aggregate blob bytes.
        var limits = PreimageLimits(
            ElementLimit(unsigned(p[1])), ByteLimit(unsigned(p[2])), ByteLimit(unsigned(p[3]))
        )
        if p[0] == "PE":
            # Build explicit descriptors over a retained local native pool.
            var records = List[Preimage]()
            var pool = List[UInt8]()
            if p[5] != "-":
                var texts = p[5].split(";")
                # Bound actual trusted utility descriptors.
                if len(texts) > 256:
                    raise Error("records")
                # Each tuple independently checks the nominal uint32 service before narrowing.
                for index in range(len(texts)):
                    var pair = String(texts[index]).split(":")
                    # Malformed tuple text must not select a production span.
                    if len(pair) != 2:
                        raise Error("record text")
                    var service = unsigned(String(pair[0]))
                    # Prevent silent narrowing from UInt64 into the service domain.
                    if service > UInt64(4294967295):
                        raise Error("service")
                    var bytes = unhex(String(pair[1]))
                    # The adapter owns at most 32 KiB, irrespective of the larger caller policy.
                    if len(bytes) > 32768 - len(pool):
                        raise Error("pool")
                    records.append(
                        Preimage(ServiceIndex(UInt32(service)), BlobSpan(len(pool), len(bytes)))
                    )
                    # Copy each trusted tuple payload into the stable pool before encoding.
                    for i in range(len(bytes)):
                        pool.append(bytes[i])
            print_write(
                encode_preimages_borrowed(
                    Span(records), Span(pool), limits, Span(output)[: capacity(p[4], 32768)]
                ),
                Span(output),
            )
        else:
            # Sentinel descriptors detect even a late partial decoder write.
            var wire = unhex(p[5])
            var records = List[Preimage](
                length=capacity(p[4], 256), fill=Preimage(ServiceIndex(999), BlobSpan(333, 444))
            )
            var result = decode_preimages_borrowed(Span(wire), limits, Span(records))
            # Failed records contain no output count; inspect the entire caller storage.
            if result.isa[Failure]():
                for i in range(len(records)):
                    # All descriptor fields must retain their exact original sentinel.
                    if (
                        records[i].service.value != 999
                        or records[i].blob.offset != 333
                        or records[i].blob.length != 444
                    ):
                        raise Error("partial record commit")
                print(result[Failure].reason())
                return
            var count = result[SequenceInfo].count
            var consumed = result[SequenceInfo].consumed
            check_capture(wire, 3, ByteLimit(0), limits, consumed)
            var encoded = encode_preimages_borrowed(
                Span(records)[:count], Span(wire), limits, Span(output)
            )
            # Whole-extrinsic reconstruction must agree with the decoded prefix extent.
            if not encoded.isa[Written]() or encoded[Written].written != consumed:
                raise Error("preimages reconstruction extent")
            # Confirm canonical byte identity rather than relying on the encoder's success tag alone.
            for i in range(consumed):
                if output[i] != wire[i]:
                    raise Error("preimages reconstruction bytes")
            var text = String()
            # Print actual service/payload tuples so the independent oracle checks semantic values too.
            for i in range(count):
                if i != 0:
                    # Tuple separators appear only between records.
                    text += ";"
                var blob = records[i].blob.copy()
                text += (
                    String(records[i].service.value)
                    + ":"
                    + hex_text(Span(wire)[blob.offset : blob.offset + blob.length])
                )
            # An empty extrinsic still has a complete canonical count prefix.
            if count == 0:
                text = "-"
            print(text + " " + String(consumed))
    else:
        # Unknown command or wrong arity is confined to the test utility layer.
        print("inputerror")


# Parse full-digest fields into nominal types, then compare native values and canonical reconstruction.
def digest_request(p: List[String]) raises:
    var output = List[UInt8](length=32768, fill=77)
    # Encoding supplies every field, including both distinct hashes and five distinct metrics.
    if len(p) == 14 and p[0] == "E":
        var service = unsigned(p[3])
        var code = unhex(p[4])
        var hash = unhex(p[5])
        var tag = signed(p[7])
        # Reject incorrect widths/domain ranges before constructing nominal public fields.
        if service > UInt64(4294967295) or len(code) != 32 or len(hash) != 32 or tag < 0 or tag > 6:
            raise Error("digest field")
        var c = Array[UInt8, 32](fill=0)
        var h = Array[UInt8, 32](fill=0)
        # Own every checked fixed hash byte rather than retaining a mutable input pointer.
        for i in range(32):
            c[i] = code[i]
            h[i] = hash[i]
        var pool = unhex(p[8])
        var work = WorkOutput(WorkFailure(UInt64(tag)))
        # Only success borrows a payload span.
        if tag == 0:
            work = WorkOutput(BlobSpan(0, len(pool)))
        var value = WorkDigest(
            ServiceIndex(UInt32(service)),
            CodeHash(c^),
            PayloadHash(h^),
            Gas(unsigned(p[6])),
            work^,
            RefineLoad(
                Gas(unsigned(p[9])),
                ImportCount(unsigned(p[10])),
                ExtrinsicCount(unsigned(p[11])),
                ExtrinsicBytes(unsigned(p[12])),
                ExportCount(unsigned(p[13])),
            ),
        )
        print_write(
            encode_digest_borrowed(
                value^, Span(pool), ByteLimit(unsigned(p[1])), Span(output)[: capacity(p[2], 32768)]
            ),
            Span(output),
        )
    elif len(p) == 3 and p[0] == "D":
        # Successful spans retain original full-input coordinates throughout reconstruction.
        var wire = unhex(p[2])
        var limit = ByteLimit(unsigned(p[1]))
        var result = decode_digest_borrowed(Span(wire), limit)
        # Invalid final metrics expose no fixed fields or output payload either.
        if result.isa[Failure]():
            print(result[Failure].reason())
            return
        var parsed = result[Decoded[WorkDigest]].copy()
        check_capture(
            wire,
            4,
            limit,
            PreimageLimits(ElementLimit(0), ByteLimit(0), ByteLimit(0)),
            parsed.consumed,
        )
        var encoded = encode_digest_borrowed(parsed.value.copy(), Span(wire), limit, Span(output))
        # Check complete canonical reconstruction, excluding any caller trailing fields.
        if not encoded.isa[Written]() or encoded[Written].written != parsed.consumed:
            raise Error("digest reconstruction extent")
        # Verify every fixed field, discriminator, payload and metric byte.
        for i in range(parsed.consumed):
            if wire[i] != output[i]:
                raise Error("digest reconstruction bytes")
        var value = parsed.value.copy()
        var tag: UInt64 = 0
        var payload = String("-")
        # Only the success branch contains a borrowed blob descriptor.
        if value.output.isa[BlobSpan]():
            var blob = value.output[BlobSpan].copy()
            payload = hex_text(Span(wire)[blob.offset : blob.offset + blob.length])
        else:
            # Error variants contain only their discriminator.
            tag = value.output[WorkFailure].tag
        print(
            String(value.service.value)
            + " "
            + hex_text(Span(value.code_hash.bytes))
            + " "
            + hex_text(Span(value.payload_hash.bytes))
            + " "
            + String(value.accumulate_gas.value)
            + " "
            + String(tag)
            + " "
            + payload
            + " "
            + String(value.refine.gas_used.value)
            + " "
            + String(value.refine.imports.value)
            + " "
            + String(value.refine.extrinsic_count.value)
            + " "
            + String(value.refine.extrinsic_size.value)
            + " "
            + String(value.refine.exports.value)
            + " "
            + String(parsed.consumed)
        )
    else:
        # Invalid utility commands never invoke a decoder with guessed arguments.
        print("inputerror")


# Process a native file batch; Python only supplies shared fixtures and checks printed responses externally.
def main() raises:
    var args = argv()
    # Select an explicit family so identically named scalar/digest commands cannot be confused.
    if len(args) != 3:
        raise Error("usage: driver family requests")
    var text: String
    # Native file ownership is scoped; no Python module is loaded for test/protocol execution.
    with open(args[2], "r") as file:
        text = file.read()
    var lines = text.split("\n")
    # Every actual request gets exactly one response, including malformed trusted text.
    for index in range(len(lines)):
        var line = String(lines[index])
        # File-final newline is not a request.
        if line == "":
            continue
        var parts = line.split(" ")
        var p = List[String]()
        # Own textual fields so no temporary StringSpan outlives its request line.
        for i in range(len(parts)):
            p.append(String(parts[i]))
        try:
            # Dispatch only the declared native family; parser failures remain local to this line.
            if args[1] == "natural" or args[1] == "fixed":
                scalar_request(p^, args[1] == "fixed")
            elif args[1] == "bounded":
                bounded_request(p^)
            elif args[1] == "composite":
                composite_request(p^)
            elif args[1] == "digest":
                digest_request(p^)
            else:
                # Unknown families must not silently select a different protocol schema.
                raise Error("family")
        except:
            # Test-text parse errors must not terminate the remaining shared batch.
            print("inputerror")
