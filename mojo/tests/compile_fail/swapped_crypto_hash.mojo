from std.collections import Array
from crypto.primitives import Blake2bHash, KeccakHash


# Deliberate type/API misuse must fail for its intended domain or inaccessible payload.
def main():
    var value = KeccakHash(Array[UInt8, 32](fill=0))
    var wrong: Blake2bHash = value
    _ = wrong
