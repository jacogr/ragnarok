from std.collections import Span
from codec.types import *
from codec.owned import *
from codec.scalar import decode_natural
from codec.bounded import decode_bytes_borrowed
from codec.composite import read_tag, Tagged, decode_preimages_borrowed
from codec.digest import decode_digest_borrowed, WorkDigest, metrics


# Decode expected payload coordinates from the original test input, independently of owned extraction.
def expected_blobs(
    data: Span[mut=False, UInt8, _], kind: Int, limit: ByteLimit, limits: PreimageLimits
) -> List[BlobSpan]:
    var result = List[BlobSpan]()
    if kind == 0:
        # The byte-string schema contains one blob even when its length is zero.
        var decoded = decode_bytes_borrowed(data, limit)
        result.append(decoded[Decoded[BlobSpan]].value.copy())
    elif kind == 1 or kind == 2:
        # Only present/success alternatives contain a blob; payload-free alternatives contain none.
        var decoded = read_tag(
            data, UInt64(1 if kind == 1 else 6), UInt64(1 if kind == 1 else 0), limit
        )
        var tag = decoded[Tagged].copy()
        if tag.tag == UInt64(1 if kind == 1 else 0):
            result.append(tag.blob.copy())
    elif kind == 3:
        # Each tuple's service and payload are selected from the independently decoded descriptor array.
        var prefix = decode_natural(data)
        var count = Int(prefix[Decoded[JamNatural]].value.value)
        var records = List[Preimage](length=count, fill=Preimage(ServiceIndex(0), BlobSpan(0, 0)))
        var decoded = decode_preimages_borrowed(data, limits, Span(records))
        _ = decoded[SequenceInfo]
        for i in range(count):
            result.append(records[i].blob.copy())
    else:
        # A digest's output coordinates must remain relative to its complete enclosing wire input.
        var decoded = decode_digest_borrowed(data, limit)
        var digest = decoded[Decoded[WorkDigest]].value.copy()
        if digest.output.isa[BlobSpan]():
            result.append(digest.output[BlobSpan].copy())
    return result^


# Check capture isolation, owner-bound extraction and canonical re-emission for each successful shared decode.
def check_capture(
    mut wire: List[UInt8], kind: Int, limit: ByteLimit, limits: PreimageLimits, consumed: Int
) raises:
    var loaded = capture(Span(wire), kind, limit, limits)
    # A successful borrowed decode must have an equivalent retained snapshot.
    if loaded.isa[Failure]():
        raise Error("owned capture failed: " + loaded[Failure].reason())
    var frame = loaded[OwnedFrame].copy()
    try:
        var original = wire.copy()
        var expected = expected_blobs(Span(original), kind, limit, limits)
        # Erase every caller input byte, including trailing fields, after capture has finished borrowing it.
        for i in range(len(wire)):
            wire[i] = 99
        var info = owned_info(frame)
        # Ownership retains only the consumed canonical prefix, never unrelated trailing fields.
        if (
            not info.isa[OwnedInfo]()
            or info[OwnedInfo].consumed != consumed
            or info[OwnedInfo].kind != kind
            or info[OwnedInfo].blob_count != len(expected)
        ):
            raise Error("owned metadata")
        var output = List[UInt8](length=consumed, fill=77)
        var encoded = encode_owned(frame, Span(output))
        # The complete frame must remain independent of the changed caller bytes.
        if not encoded.isa[Written]() or encoded[Written].written != consumed:
            raise Error("owned re-encoding")
        # Compare each retained original byte with the canonical snapshot output.
        for i in range(consumed):
            if output[i] != original[i]:
                raise Error("owned mutation isolation")
        # Every retained blob is extracted only through this owner and a scalar index.
        for index in range(info[OwnedInfo].blob_count):
            var length = owned_blob_length(frame, index)
            if not length.isa[Int]():
                # Invalid owner metadata cannot produce a buffer allocation.
                raise Error("owned blob length")
            var bytes = List[UInt8](length=length[Int], fill=77)
            var copied = copy_owned_blob(frame, index, Span(bytes))
            # Complete payload extraction must agree with its length-only metadata.
            if not copied.isa[Written]() or copied[Written].written != len(bytes):
                raise Error("owned payload copy")
            if len(bytes) != expected[index].length:
                # A valid-looking wrong span must not pass a length-only extraction check.
                raise Error("owned expected payload length")
            for i in range(len(bytes)):
                # Check every copied byte after the caller's entire backing input has been overwritten.
                if bytes[i] != original[expected[index].offset + i]:
                    raise Error("owned expected payload byte")
        # Schema-specific metadata operations must not expose source coordinates.
        if kind == 1:
            var optional = owned_optional_info(frame)
            if not optional.isa[OwnedOptionalInfo]():
                # An owned optional must retain its presence/absence alternative.
                raise Error("owned optional metadata")
        elif kind == 2:
            var work = owned_work_info(frame)
            if not work.isa[OwnedWorkInfo]():
                # Work errors are valid values rather than failed ownership operations.
                raise Error("owned work metadata")
        elif kind == 4:
            var digest = owned_digest_info(frame)
            if not digest.isa[OwnedDigestInfo]():
                # Every copied fixed field must remain retrievable after original input mutation.
                raise Error("owned digest metadata")
        # Restore the original local test owner before its borrowed response coordinates are used again.
        wire = original^
    finally:
        # Exactly one original handle releases storage; the loaded result and frame copy are aliases.
        release(frame)
