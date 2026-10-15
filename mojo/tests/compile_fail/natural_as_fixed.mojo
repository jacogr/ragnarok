from codec.scalar import encode_fixed
from codec.types import JamNatural, ByteWidth


# Deliberate type/API misuse must fail for its intended domain or inaccessible payload.
def main():
    _ = encode_fixed(JamNatural(1), ByteWidth(1))
