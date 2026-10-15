from std.collections import Array
from crypto.primitives import Blake2bHash, EdPublicKey


# Deliberate type/API misuse must fail for its intended domain or inaccessible payload.
def main():
    var value = Blake2bHash(Array[UInt8, 32](fill=0))
    var wrong: EdPublicKey = value
    _ = wrong
