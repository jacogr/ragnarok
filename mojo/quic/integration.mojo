from std.collections import Array, Span
from std.os.path import getsize
from codec.types import *
from codec.owned import *
from crypto.primitives import PublicBytes, Blake2bHash, blake2b256


comptime WIRE_CAP = 1024 * 1024 + 256
comptime PreimageKey = PublicBytes[20, 32]


# A verified response retains both an opaque immutable codec snapshot and its owned serialization.
# Copies are aliases for the explicit snapshot release contract; one stream owner releases exactly once.
@fieldwise_init
struct VerifiedDigest(Copyable, Movable):
    var owner: OwnedFrame
    var wire: List[UInt8]


# Trusted bounded preimage bank; no network bytes select filesystem paths or unvalidated indices.
@fieldwise_init
struct IntegrationBank(Copyable, Movable):
    var wires: List[List[UInt8]]
    var keys: List[PreimageKey]


# A missing verified value owns no snapshot allocation or serialization buffer.
def empty_verified() -> VerifiedDigest:
    return VerifiedDigest(OwnedFrame(None), List[UInt8]())


# Hash raw preimage bytes into a distinct CE key domain, without reinterpreting any digest field as a hash assertion.
def preimage_key(data: Span[mut=False, UInt8, _]) -> CheckedResult[PreimageKey]:
    var hashed = blake2b256(data)
    # A backend failure cannot produce a default requested content key.
    if not hashed.isa[Blake2bHash]():
        return CheckedResult[PreimageKey](fail["backendfailure"]())
    var hash = hashed[Blake2bHash].copy()
    return CheckedResult[PreimageKey](PreimageKey(hash.bytes.copy()))


# Load only eight known public controller fixtures before registering any TLS/stream callback.
def load_bank(directory: String) raises -> IntegrationBank:
    # Missing controls must not silently select the process's current working directory.
    if directory == "":
        raise Error("integration directory")
    var wires = List[List[UInt8]]()
    var keys = List[PreimageKey]()
    # Actual fixture sizes bound allocations independently from later untrusted network claims.
    for index in range(8):
        var path = directory + "/" + String(index) + ".bin"
        var size = getsize(path)
        if size < 1 or size > WIRE_CAP:
            # Reject unsupported controller storage before reading it into a native list.
            raise Error("integration fixture size")
        var wire: List[UInt8]
        with open(path, "r") as file:
            wire = file.read_bytes()
        if len(wire) < 1 or len(wire) > WIRE_CAP:
            # Recheck the trusted read in case the file changed after stat.
            raise Error("integration fixture changed")
        var key = preimage_key(Span(wire))
        if not key.isa[PreimageKey]():
            # Failed hashing must not seed a valid-looking fixture lookup entry.
            raise Error("integration fixture hash")
        keys.append(key[PreimageKey].copy())
        wires.append(wire^)
    return IntegrationBank(wires^, keys^)


# Exact complete content-key equality selects an entry; minus one is never used as a list index.
def find_fixture(bank: IntegrationBank, key: Span[mut=False, UInt8, _]) -> Int:
    # No truncation or padding may turn malformed CE query data into a lookup key.
    if len(key) != 32:
        return -1
    for index in range(len(bank.keys)):
        var matches = True
        # Every byte must agree, independently of any shared prefix or first-byte dispatch optimization.
        for i in range(32):
            if key[i] != bank.keys[index].bytes[i]:
                matches = False
                break
        if matches:
            # The caller checks this explicit nonnegative index before accessing fixture bytes.
            return index
    return -1


# Capture a standalone digest, overwrite its original input, then hash only the owner's canonical serialization.
def capture_digest(
    data: Span[mut=True, UInt8, _], expected: PreimageKey
) -> CheckedResult[VerifiedDigest]:
    var loaded = capture(
        data, 4, ByteLimit(1024 * 1024), PreimageLimits(ElementLimit(0), ByteLimit(0), ByteLimit(0))
    )
    # A malformed digest produces no application snapshot or serialized response.
    if not loaded.isa[OwnedFrame]():
        return CheckedResult[VerifiedDigest](loaded[Failure].copy())
    var owner = loaded[OwnedFrame].copy()
    var transferred = False
    try:
        var info = owned_info(owner)
        if not info.isa[OwnedInfo]():
            # Missing/corrupt owner metadata cannot authorize a response allocation.
            return CheckedResult[VerifiedDigest](fail["invalidowner"]())
        if info[OwnedInfo].consumed != len(data):
            # A successful prefix decoder needs a separate standalone-frame trailing-data guard.
            return CheckedResult[VerifiedDigest](fail["trailing"]())
        for i in range(len(data)):
            # Actively reuse the original received/scratch bytes before serialization or hashing.
            data[i] = 165
        var wire = List[UInt8](length=len(data), fill=0)
        var written = encode_owned(owner, Span(wire))
        if not written.isa[Written]() or written[Written].written != len(wire):
            # Only the immutable owner may supply bytes after original-input reuse.
            return CheckedResult[VerifiedDigest](fail["invalidowner"]())
        var key = preimage_key(Span(wire))
        if not key.isa[PreimageKey]():
            # A failed primitive has no default content-key verdict.
            return CheckedResult[VerifiedDigest](key[Failure].copy())
        var actual = key[PreimageKey].copy()
        for i in range(32):
            if actual.bytes[i] != expected.bytes[i]:
                # Bind the complete preimage serialization to the independently retained actual CE query.
                return CheckedResult[VerifiedDigest](fail["hashmismatch"]())
        transferred = True
        return CheckedResult[VerifiedDigest](VerifiedDigest(owner.copy(), wire^))
    finally:
        # Failed captures retire their sole snapshot owner; successful snapshots transfer to one stream owner.
        if not transferred:
            release(owner)


# Retire exactly one stream-owned snapshot before its serialized response storage is released.
def release_verified(mut value: VerifiedDigest):
    release(value.owner)
    value.wire = List[UInt8]()


# Render composed error categories without changing the underlying typed codec/crypto failure contract.
def reject_reason(failure: Failure) -> String:
    var reason = failure.reason()
    if reason == "hashmismatch":
        # A valid standalone digest may still be the wrong requested preimage.
        return String("HashMismatch")
    elif reason == "trailing":
        # Standalone composition rejects otherwise valid prefixes with unrelated suffix data.
        return String("Trailing")
    elif reason == "invalidowner":
        # Ownership failures never select default serialized bytes.
        return String("Owner")
    elif reason == "backendfailure":
        # Crypto failures cannot be conflated with an invalid protocol encoding.
        return String("Crypto")
    else:
        # Preserve exact leaf reasons in their native result; the integration log reports their composed category.
        return String("Codec")


# Fuzz the production standalone capture/hash composition; successful snapshots must survive input reuse.
def composition_selftest() raises:
    var seed: UInt64 = 0x434F444543
    var successful = 0
    # Malformed bodies can only yield typed failure; successful captures must retain byte-exact serialization.
    for iteration in range(10000):
        var wire = List[UInt8](length=iteration % 257, fill=0)
        # Fill a bounded candidate without letting hostile claims select an allocation.
        for i in range(len(wire)):
            seed ^= seed << UInt64(13)
            seed ^= seed >> UInt64(7)
            seed ^= seed << UInt64(17)
            wire[i] = UInt8(seed & 255)
        # Periodically insert a canonical zero-output digest, including complete and trailing-data forms.
        if iteration % 5 == 0:
            wire = List[UInt8](length=82 + iteration % 2, fill=0)
            wire[76] = 2
        var original = wire.copy()
        var key = preimage_key(Span(wire))
        # A primitive failure cannot become an expected content key.
        if not key.isa[PreimageKey]():
            raise Error("selftest hash backend")
        var result = capture_digest(Span(wire), key[PreimageKey].copy())
        # Only the verified branch owns a snapshot; rejected/trailing frames own none.
        if result.isa[VerifiedDigest]():
            successful += 1
            var value = result[VerifiedDigest].copy()
            try:
                # Capture must retain the complete standalone message and no unrelated suffix.
                if len(value.wire) != len(original):
                    raise Error("capture extent")
                # Input reuse must leave every owner-derived serialized byte intact.
                for i in range(len(original)):
                    # Reject either a stale snapshot reference or incomplete receive-buffer overwrite.
                    if value.wire[i] != original[i] or wire[i] != 165:
                        raise Error("capture input reuse")
            finally:
                # One explicit owner retires even when an invariant check raises.
                release_verified(value)
    # Positive fixtures prevent an always-rejecting implementation from passing fuzz coverage.
    if successful < 1000:
        raise Error("selftest positive captures")
    print("Mojo integration selftest: 10000 owned codec/hash cases passed")
