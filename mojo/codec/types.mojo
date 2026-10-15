from std.utils import Variant


# Nominal UInt64 domains: distinct specializations prevent swapping protocol values or limits.
@fieldwise_init
struct Quantity[kind: Int](Copyable, Movable):
    var value: UInt64


comptime JamNatural = Quantity[0]
comptime FixedUnsigned = Quantity[1]
comptime ByteLimit = Quantity[2]
comptime ElementLimit = Quantity[3]
comptime Gas = Quantity[4]
comptime ImportCount = Quantity[5]
comptime ExtrinsicCount = Quantity[6]
comptime ExtrinsicBytes = Quantity[7]
comptime ExportCount = Quantity[8]


# Requested signed width; APIs validate it before any arithmetic or byte access.
@fieldwise_init
struct ByteWidth(Copyable, Movable):
    var value: Int


# A nominal failure reason has fixed integer storage: malformed input never allocates error text.
@fieldwise_init
struct Failure(Copyable, Movable):
    var _code: Int

    # Render a reason only at diagnostic boundaries; the decoder stores no dynamic String.
    def reason(self) -> String:
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        if self._code == 0:
            return String("uninitialized")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 1:
            return String("aliasedbuffers")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 2:
            return String("allocationfailure")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 3:
            return String("backendfailure")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 4:
            return String("bs:2")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 5:
            return String("bs:3")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 6:
            return String("bs:4")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 7:
            return String("bs:5")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 8:
            return String("bs:6")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 9:
            return String("bs:7")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 10:
            return String("invalidindex")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 11:
            return String("invalidlength")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 12:
            return String("invalidowner")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 13:
            return String("invalidseed")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 14:
            return String("invalidspan")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 15:
            return String("invalidtag")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 16:
            return String("invalidwidth")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 17:
            return String("lengthoverflow")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 18:
            return String("limitexceeded")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 19:
            return String("noncanonical")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 20:
            return String("outofrange")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 21:
            return String("outputtoosmall")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 22:
            return String("truncated")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 23:
            return String("valueoutofrange")
        # Preserve the exact shared test-protocol diagnostic for this nominal failure.
        elif self._code == 24:
            return String("wrongschema")
        # Standalone composed frames reject unrelated suffix bytes.
        elif self._code == 25:
            return String("trailing")
        # Cryptographic content binding is independent of successful codec validation.
        elif self._code == 26:
            return String("hashmismatch")
        # Assurances configuration and validator bounds retain independent failure reasons.
        elif self._code == 27:
            return String("invalidconfig")
        elif self._code == 28:
            # A structurally encoded validator can still be outside the configured set.
            return String("invalidvalidator")
        # Context verification requires an exact validator-key mapping.
        elif self._code == 29:
            return String("invalidkeyset")
        # Every assurance anchor must match the externally supplied parent.
        elif self._code == 30:
            return String("wrongparent")
        # A rejected ordinary signature provides no verified count.
        elif self._code == 31:
            return String("invalidsignature")
        else:
            # Corrupted caller metadata cannot fabricate a successful result.
            return String("uninitialized")


# Successful decode metadata lives exclusively in this alternative of a checked Variant.
@fieldwise_init
struct Decoded[T: Copyable & Deinitable](Copyable, Movable):
    var value: Self.T
    var consumed: Int


# Completed output extent is available only after the result's success discriminator is checked.
@fieldwise_init
struct Written(Copyable, Movable):
    var written: Int


# Detached coordinates are explicitly borrowed; the original pool must remain stable through use.
@fieldwise_init
struct BlobSpan(Copyable, Movable):
    var offset: Int
    var length: Int


# Fixed service indices retain their own four-byte nominal domain.
@fieldwise_init
struct ServiceIndex(Copyable, Movable):
    var value: UInt32


# Absence and payload-free work failures contain no span.
@fieldwise_init
struct Absent(Copyable, Movable):
    pass


# One of the six payload-free C.2 work failures, validated before construction by the decoder.
@fieldwise_init
struct WorkFailure(Copyable, Movable):
    var tag: UInt64


comptime OptionalBlob = Variant[Absent, BlobSpan]
comptime WorkOutput = Variant[BlobSpan, WorkFailure]
comptime WriteResult = CheckedResult[Written]


# Full nested preimage descriptor borrowing the same pool as its enclosing extrinsic.
@fieldwise_init
struct Preimage(Copyable, Movable):
    var service: ServiceIndex
    var blob: BlobSpan


# Distinct item/per-blob/aggregate limits preserve the caller's independent resource policies.
@fieldwise_init
struct PreimageLimits(Copyable, Movable):
    var items: ElementLimit
    var per_blob: ByteLimit
    var total_bytes: ByteLimit


# Default-initialized results are failures; success metadata exists only in a checked union alternative.
struct CheckedResult[T: Copyable & Deinitable](Copyable, Movable):
    var _state: Variant[Failure, Self.T]

    # Default construction never creates a decoded value, hash, signature or owner.
    def __init__(out self):
        self._state = Variant[Failure, Self.T](fail["uninitialized"]())

    # Explicit success construction transfers an already validated native value into the union.
    def __init__(out self, var value: Self.T):
        self._state = Variant[Failure, Self.T](value^)

    # Failure construction stores only its reason, without any progress or payload fields.
    def __init__(out self, var failure: Failure):
        self._state = Variant[Failure, Self.T](failure^)

    # Select an alternative before accessing its fields, mirroring the public standard Variant API.
    def isa[V: AnyType](self) -> Bool:
        return self._state.isa[V]()

    # Checked extraction copies value data only after the standard union discriminator assertion.
    def __getitem_param__[V: Copyable & Deinitable](mut self) -> V:
        return self._state[V].copy()


# Select a nominal failure code at compile time; decoding never constructs dynamic error text.
def fail[name: String]() -> Failure:
    # uninitialized retains its distinct shared contract reason.
    comptime if name == "uninitialized":
        return Failure(0)
    # aliasedbuffers retains its distinct shared contract reason.
    elif name == "aliasedbuffers":
        return Failure(1)
    # allocationfailure retains its distinct shared contract reason.
    elif name == "allocationfailure":
        return Failure(2)
    # backendfailure retains its distinct shared contract reason.
    elif name == "backendfailure":
        return Failure(3)
    # bs:2 retains its distinct shared contract reason.
    elif name == "bs:2":
        return Failure(4)
    # bs:3 retains its distinct shared contract reason.
    elif name == "bs:3":
        return Failure(5)
    # bs:4 retains its distinct shared contract reason.
    elif name == "bs:4":
        return Failure(6)
    # bs:5 retains its distinct shared contract reason.
    elif name == "bs:5":
        return Failure(7)
    # bs:6 retains its distinct shared contract reason.
    elif name == "bs:6":
        return Failure(8)
    # bs:7 retains its distinct shared contract reason.
    elif name == "bs:7":
        return Failure(9)
    # invalidindex retains its distinct shared contract reason.
    elif name == "invalidindex":
        return Failure(10)
    # invalidlength retains its distinct shared contract reason.
    elif name == "invalidlength":
        return Failure(11)
    # invalidowner retains its distinct shared contract reason.
    elif name == "invalidowner":
        return Failure(12)
    # invalidseed retains its distinct shared contract reason.
    elif name == "invalidseed":
        return Failure(13)
    # invalidspan retains its distinct shared contract reason.
    elif name == "invalidspan":
        return Failure(14)
    # invalidtag retains its distinct shared contract reason.
    elif name == "invalidtag":
        return Failure(15)
    # invalidwidth retains its distinct shared contract reason.
    elif name == "invalidwidth":
        return Failure(16)
    # lengthoverflow retains its distinct shared contract reason.
    elif name == "lengthoverflow":
        return Failure(17)
    # limitexceeded retains its distinct shared contract reason.
    elif name == "limitexceeded":
        return Failure(18)
    # noncanonical retains its distinct shared contract reason.
    elif name == "noncanonical":
        return Failure(19)
    # outofrange retains its distinct shared contract reason.
    elif name == "outofrange":
        return Failure(20)
    # outputtoosmall retains its distinct shared contract reason.
    elif name == "outputtoosmall":
        return Failure(21)
    # truncated retains its distinct shared contract reason.
    elif name == "truncated":
        return Failure(22)
    # valueoutofrange retains its distinct shared contract reason.
    elif name == "valueoutofrange":
        return Failure(23)
    # wrongschema retains its distinct shared contract reason.
    elif name == "wrongschema":
        return Failure(24)
    # Standalone composed frames reject trailing bytes even after a valid prefix decode.
    elif name == "trailing":
        return Failure(25)
    # A valid codec snapshot still must match its independently retained requested content key.
    elif name == "hashmismatch":
        return Failure(26)
    # Assurances resource configuration is checked before any input access.
    elif name == "invalidconfig":
        return Failure(27)
    # Validator-index range errors remain distinct from ordering failures.
    elif name == "invalidvalidator":
        return Failure(28)
    # A partial or oversized validator table cannot establish the intended key mapping.
    elif name == "invalidkeyset":
        return Failure(29)
    # Anchor/expected-parent mismatch is independent of signature validity.
    elif name == "wrongparent":
        return Failure(30)
    # The existing provider rejected the ordinary Ed25519 credential.
    elif name == "invalidsignature":
        return Failure(31)
    else:
        # An unsupported reason remains a failure, never a fabricated success.
        return Failure(0)
