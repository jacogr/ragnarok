from codec.scalar import encode_natural


# Deliberate type/API misuse must fail for its intended domain or inaccessible payload.
def main():
    _ = encode_natural(UInt64(1))
