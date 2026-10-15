from std.collections import Span


# Parse trusted adapter UInt64 decimal text without truncating or accepting overflow/signs.
def unsigned(text: String) raises -> UInt64:
    var bytes = text.as_bytes()
    # Empty strings cannot denote zero implicitly.
    if len(bytes) == 0:
        raise Error("empty integer")
    var value: UInt64 = 0
    # Validate each digit and prove multiply/add before committing the next value.
    for i in range(len(bytes)):
        var digit = Int(bytes[i]) - 48
        # Disallow negative/positive signs and any nondecimal alphabet.
        if digit < 0 or digit > 9:
            raise Error("integer digit")
        # Maximum quotient/remainder proves the exact UInt64 range.
        if value > UInt64(1844674407370955161) or (
            value == UInt64(1844674407370955161) and digit > 5
        ):
            raise Error("integer overflow")
        value = value * 10 + UInt64(digit)
    return value


# Validate a signed host integer using the standard checked textual constructor.
def signed(text: String) raises -> Int:
    return Int(text)


# Bound trusted adapter allocations independently from protocol resource ceilings.
def capacity(text: String, maximum: Int) raises -> Int:
    var value = signed(text)
    # Reject negative or large utility capacities before allocating native storage.
    if value < 0 or value > maximum:
        raise Error("capacity")
    return value


# Decode bounded lowercase hex; dash denotes an explicit empty adapter payload.
def unhex(text: String) raises -> List[UInt8]:
    var result = List[UInt8]()
    # Preserve empty payload tokens even between other whitespace-separated fields.
    if text == "-":
        return result^
    var chars = text.as_bytes()
    # No input-derived allocation may exceed the adapter's established 32-KiB capacity.
    if len(chars) % 2 != 0 or len(chars) > 65536:
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


# Encode exactly a retained byte view; empty_token controls the primitive versus container protocol.
def hex_text(data: Span[mut=False, UInt8, _], empty_token: Bool = True) -> String:
    # Containers use dash for emptiness, while primitive encoders print an empty line.
    if len(data) == 0 and empty_token:
        return String("-")
    var result = String()
    var alphabet = String("0123456789abcdef")
    # Select two already bounded characters per octet without locale-dependent formatting.
    for i in range(len(data)):
        result += alphabet[codepoint=Int(data[i]) // 16]
        result += alphabet[codepoint=Int(data[i]) % 16]
    return result^


# Assert the entire destination remains unchanged on failure, including unused trailing storage.
def unchanged(data: Span[mut=False, UInt8, _]) raises:
    # Inspect every byte, rather than just the extent that an erroneous decoder might claim.
    for i in range(len(data)):
        # Any partial commit violates the codec's documented atomic-failure contract.
        if data[i] != 77:
            raise Error("failed operation mutated destination")
