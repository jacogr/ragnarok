from std.collections import Span
from codec.bounded import decode_bytes_borrowed
from codec.types import ElementLimit


# Deliberate type/API misuse must fail for its intended domain or inaccessible payload.
def main():
    var wire: List[UInt8] = [0]
    _ = decode_bytes_borrowed(Span(wire), ElementLimit(1))
